import web
import psycopg2
import argparse
import math
import string

urls = (
    '/', 'index',
    '/l?(.+)', 'location',
)

class index:
    def GET(self):
        render = web.template.render('templates/')
        return render.geo();
        # return "Hey! POST a string with 'latitude longitude heading'"
    def POST(self):
        data = web.data()
        return data
        (lat, lng, head) = string.split(data)
        #return "" + lat + " " +  lng + " " + head
        return query(lat, lng)

class location:
    def GET(self, name):
        data = web.input()
        lat = data.lat
        lng = data.lng
        return sweep(lat, lng)

def sweep(lat, lng):
    buildings = query(lat,lng)

    result = ''
    for bldg in buildings:
        result = "{0} {1} \n".format(result, str(bldg))

    return result


def query(latitude, longitude):
    distance = 200

    conn = psycopg2.connect("dbname=gis")
    cur = conn.cursor()
    
    query = """
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
    """ % {"distance": distance, "latitude": latitude, "longitude": longitude}
    
    cur.execute(query);

    buildings = []
    for row in cur:
        (name, lp, lh, rp, rh) = row
        buildings.append(Building(name, lp, lh, rp, rh))

    cur.close()
    conn.close()

    return buildings
    

def toRad(degree):
    return float(degree) * math.pi / 180

class Building:
    def __init__(self, name, lpoint, lheading, rpoint, rheading):
        self.name = name
        self.lp = lpoint
        self.lh = lheading
        self.rp = rpoint
        self.rh = rheading

    def __str__(self):
        return "{0}\t{1}\t{2}".format(self.name, self.lh, self.rh)


 
if __name__ == "__main__":
    app = web.application(urls, globals())
    app.run()


