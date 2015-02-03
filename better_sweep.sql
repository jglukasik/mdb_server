CREATE OR REPLACE 
  FUNCTION betterSweep(lng double precision, lat double precision, distance double precision) 
  RETURNS table(building_name text, heading integer) AS
$BODY$
BEGIN
FOR degree_step IN 
    (SELECT COALESCE(lhead, rhead) as headings FROM getBuildingsFixed(lng, lat, distance) t(bName text, lPoint text, lHead double precision, rPoint text, rHead double precision) )
    LOOP
  RETURN QUERY 
    SELECT name, degree_step
    FROM planet_osm_polygon
    WHERE
    
    ST_Intersects(
      ST_Transform(
        ST_MakeLine(
          ARRAY[
            ST_SetSRID(ST_MakePoint(lng, lat)::geometry, 4326),
            ST_Project(ST_MakePoint(lng, lat), distance, radians(degree_step))::geometry
          ]
        )
      , 900913)
    , way)
    
    AND (building='university' OR building='yes' OR building='dormitory')

    -- Quick and dirty, order by distance from the lower left corner of the building to me
    ORDER BY 
      ST_Distance(
        ST_SetSRID(ST_MakePoint(lng, lat)::geometry, 900913),
        ST_SetSRID(ST_MakePoint(
          (ST_XMax(ST_Transform(way,4326))+ST_XMin(ST_Transform(way,4326)))/2,
          (ST_YMax(ST_Transform(way,4326))+ST_YMin(ST_Transform(way,4326)))/2
          )
        , 900913)
      )

      -- Return the closest building for this degree step
      LIMIT 1;

END LOOP;
RETURN;
END
$BODY$
LANGUAGE 'plpgsql';


