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
        return query(lat, lng, head)

class location:
    def GET(self, name):
        data = web.input()
        lat = data.lat
        lng = data.lng
        return rotation(lat, lng)

def rotation(lat, lng):
    output = ''
    for heading in range(0,359,20):
        output = output + str(heading) + ': ' + query(lat, lng, heading) + '\n'
    return output

def query(latitude, longitude, heading):
    
    offset = 5
    distance = 100

    conn = psycopg2.connect("dbname=gis")
    cur = conn.cursor()

    # Make a point at our current lat/long
    position = "ST_MakePoint(%(longitude)s, %(latitude)s)" % {"longitude": longitude, "latitude": latitude}
    
    query = """
    SELECT name
    FROM planet_osm_polygon
    WHERE 
    -- Find the buildings that share area with our FOV triangle
    ST_Intersects(way, 

        -- Convert to the projection system used in osm (900913)
        ST_Transform(

            -- Make a triangle from our position, and two points 'distance' away at angles 'heading' +/- 'offset'
            ST_MakePolygon(
                ST_MakeLine(
                    ARRAY[
                        ST_SetSRID(%(point)s::geometry, 4326),
                        ST_Project(%(point)s, %(distance)s, (%(azimuth)s + %(offset)s))::geometry,
                        ST_Project(%(point)s, %(distance)s, (%(azimuth)s - %(offset)s))::geometry,
                        ST_SetSRID(%(point)s::geometry, 4326)
                    ]
                )
            )
        , 900913)
    )
    -- Fo now, just get university buildings
    AND (building='university' OR building='dormitory' OR building='yes')

    -- Return only the building closest to us (needs to be fixed!)
    ORDER BY ST_Distance(ST_SetSRID(%(point)s::geometry, 900913), way)
    LIMIT 1;
    ;
    """ % {"point": position, "distance": distance, "azimuth": toRad(heading), "offset": toRad(offset)}
    
    cur.execute(query);

    building = cur.fetchone()

    cur.close()
    conn.close()

    if (building != None):
        building_name = building[0]
        if (building_name == None):
            building_name = "Building found with no name!"
    else:
        building_name = "No building found!"

    return building_name
    

def toRad(degree):
    return float(degree) * math.pi / 180
 
if __name__ == "__main__":
    app = web.application(urls, globals())
    app.run()


