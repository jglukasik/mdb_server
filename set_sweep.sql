CREATE OR REPLACE 
  FUNCTION setSweep(lng double precision, lat double precision, distance double precision) 
  RETURNS table(building_name text) AS
$BODY$
BEGIN
RETURN QUERY 
  SELECT name
  FROM planet_osm_polygon, (SELECT num FROM number_table LIMIT 360) n
    
  WHERE
  
  ST_Intersects(
    ST_Transform(
      ST_MakeLine(
        ARRAY[
          ST_SetSRID(ST_MakePoint(lng, lat)::geometry, 4326),
          ST_Project(ST_MakePoint(lng, lat), distance, radians(n.num))::geometry
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

RETURN;
END
$BODY$
LANGUAGE 'plpgsql';


