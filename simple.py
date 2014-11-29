import web
import re
import time 
import psycopg2
import math
import json
import string
# FIXME: Not sure if this is used?
import argparse

'''
Abstract representation of a building. Holds all the necessary parts of a structure so that
we can parse sql rows into objects, and then using the toList method on each instance
we can easily move it to json.
'''
class Building:
    def __init__(self, name, lpoint, lheading, rpoint, rheading):
        self.name = name
        self.lh = str(lheading)
        self.rh = str(rheading)

        lMatch = re.search(r'^POINT\(([-]?\d+\.\d+) ([-]?\d+.\d+)\)$', lpoint).groups()
        self.lLat = lMatch[1]
        self.lLng = lMatch[0]
        
        rMatch = re.search(r'^POINT\(([-]?\d+\.\d+) ([-]?\d+.\d+)\)$', rpoint).groups()
        self.rLat = rMatch[1]
        self.rLng = rMatch[0]


    def toList(self):
      return { "bName": self.name, "lHeading": self.lh, "rHeading": self.rh, \
          "lLat": self.lLat, "lLng": self.lLng, "rLat": self.rLat, "rLng": self.rLng}


'''
Our long SQL query for doing math in the database, courtesy of J. Lukasik
'''
SQLQUERY = \
"""
WITH subquery AS (
  SELECT
    name,
    ST_AsText(ST_Transform((ST_DumpPoints(way)).geom, 4326)) AS point,
    ST_Azimuth(
      ST_Transform(
        ST_SetSRID( ST_MakePoint(%(longitude)s, %(latitude)s), 4326), 
        900913
      ),
      (ST_DumpPoints(way)).geom
    ) AS heading
    
  FROM planet_osm_polygon
  WHERE 
    (building='university' OR building='yes' OR building='dormitory')
    AND
    ST_Intersects(
      ST_Buffer(
        ST_Transform(
          ST_SetSRID(ST_MakePoint(%(longitude)s, %(latitude)s), 4326),
          900913
        ),
        %(distance)s -- Circle radius in meters
      ),
      way
    )
  GROUP BY name, way
)

SELECT l.name, l.left_point, l.left_heading, r.right_point, r.right_heading
FROM (
  SELECT
    s1.name,
    s1.point AS left_point,
    DEGREES(s1.heading) AS left_heading
  FROM subquery s1
    JOIN subquery s2 on (s1.name = s2.name)
  GROUP BY s1.name, s1.point, s1.heading
  HAVING s1.heading = MIN(s2.heading)
) l
LEFT JOIN (
  SELECT
    s3.name,
    s3.point AS right_point,
    DEGREES(s3.heading) AS right_heading
  FROM subquery s3
    JOIN subquery s2 on (s3.name = s2.name)
  GROUP BY s3.name, s3.point, s3.heading
  HAVING s3.heading = MAX(s2.heading)
) r
ON l.name = r.name
;
"""


'''
Definitions for the places at which someone is expected to hit our server.
We only expect people to hit us at / for json.
'''
urls = (
    '/', 'index',
)

'''
Definitions for what to do at a certain HTTP call at a certain URL (as defined above).
We only accept posts. Anything else should 403 (or whatever unsupported method is.)
'''
class index:
    def POST(self):
        data = web.data()
        (lat, lng, head) = string.split(data)
        return query(lat, lng)

def query(latitude, longitude):
    # Defines a distance that we care about for our query. In meters.
    distance = 200
    # Interpolates parameters for the query.
    query = SQLQUERY % {"distance": distance, "latitude": latitude, "longitude": longitude}
   
    # Open connection, initialzie a cursor, and excute the statement. 
    conn = psycopg2.connect("dbname=gis")
    cur = conn.cursor()
    cur.execute(query);

    # Reads each row given back and constructs an array of buildings toList()'s so
    # as to make JSON parsing very easy.
    buildings = []
    for row in cur:
        (name, lp, lh, rp, rh) = row
        buildings.append(Building(name, lp, lh, rp, rh).toList())

    # Close the no longer needed DB connection.
    cur.close()
    conn.close()

    # We have a container in the response JSON aptly called 'response' which contains the building
    # array, but also some information about what the caller asked us. This way, glass can know
    # that his response is X seconds old, or Y distance from his previous call.
    body = {}
    body["requestLat"] = latitude
    body["requestLng"] = longitude
    body["unixtime"]   = str(time.time())
    body["buildings"]  = buildings
    # Add it all to the container. 
    response = {}
    response["response"] = body
    # Make it into JSON and return.
    return json.dumps(response)


if __name__ == "__main__":
    # Run the program if caller.
    app = web.application(urls, globals())
    app.run()
