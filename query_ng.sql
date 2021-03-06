CREATE OR REPLACE 
  FUNCTION buildingSweep(lng double precision, lat double precision) 
  RETURNS table(building_name text, heading integer) AS
$BODY$
BEGIN
FOR degrees IN 0..359 LOOP
  RETURN QUERY 
    SELECT name, degrees
    FROM planet_osm_polygon
    WHERE
    
    ST_Intersects(
      ST_Transform(
        ST_MakeLine(
          ARRAY[
            ST_SetSRID(ST_MakePoint(lng, lat)::geometry, 4326),
            ST_Project(ST_MakePoint(lng, lat), 500, radians(degrees))::geometry
          ]
        )
      , 900913)
    , way)
    
    AND (building='university' OR building='yes')
    
    ORDER BY 
      ST_Distance(
        ST_SetSRID(ST_MakePoint(lng, lat)::geometry, 900913),
        ST_SetSRID(ST_MakePoint(
          (ST_XMax(ST_Transform(way,4326))+ST_XMin(ST_Transform(way,4326)))/2,
          (ST_YMax(ST_Transform(way,4326))+ST_YMin(ST_Transform(way,4326)))/2
          )
        , 900913)
      )

      LIMIT 1;
END LOOP;
RETURN;
END
$BODY$
LANGUAGE 'plpgsql';

SELECT building_name, MIN(heading), MAX(heading)
FROM buildingSweep(-89.403465, 43.075343)
GROUP BY building_name 
ORDER BY max;




