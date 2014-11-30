CREATE OR REPLACE
FUNCTION moveReferenceHeading(lng double precision, lat double precision, distance double precision) 
--RETURNS table(bName text, left_point text, left_heading double precision, right_point text, right_heading double precision) AS
--RETURNS text AS
RETURNS setof record AS
$$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM getBuildings(lng, lat, distance) g LEFT JOIN planet_osm_polygon p ON g.bName = p.name LOOP
IF
  ST_Intersects(
    ST_Transform(
      ST_MakeLine(
        ARRAY[
          ST_SetSRID(ST_MakePoint(lng, lat)::geometry, 4326),
          ST_Project(ST_MakePoint(lng, lat), distance, 0)::geometry
        ]
      )
    , 900913)
  , r.way)
THEN
  r.name = 'THIS ONE NORTH'; 
  RETURN NEXT (r.name, r.lpoint, r.lhead, r.rpoint, r.rhead);
ELSE
  RETURN NEXT (r.name, r.lpoint, r.lhead, r.rpoint, r.rhead);
END IF;
END LOOP;
RETURN;
END
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE
  FUNCTION getBuildings(lng double precision, lat double precision, distance double precision) 
  RETURNS table(bName text, lPoint text, lHead double precision, rPoint text, rHead double precision) AS
$$
BEGIN
RETURN QUERY
WITH subquery AS (
  SELECT
    name,
    ST_AsText(ST_Transform((ST_DumpPoints(way)).geom, 4326)) AS point,
    ST_Azimuth(
      ST_Transform(
        ST_SetSRID( ST_MakePoint(lng, lat), 4326), 
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
          ST_SetSRID(ST_MakePoint(lng, lat), 4326),
          900913
        ),
        distance -- Circle radius in meters
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
ON l.name = r.name;
END
$$
LANGUAGE 'plpgsql';

SELECT *
FROM moveReferenceHeading(-89.402343, 43.075171, 200) t(bName text, lPoint text, lHead double precision, rPoint text, rHead double precision);
--FROM getBuildings(-89.402343, 43.075171, 200);
  
 
