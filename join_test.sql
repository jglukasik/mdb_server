SELECT
  name,
  --point,
  degrees(MIN(heading)) AS left_heading,
  degrees(MAX(heading)) AS right_heading

FROM (
  SELECT
    name,
    ST_AsText(ST_Transform((ST_DumpPoints(way)).geom, 4326)) AS point,
    ST_Azimuth(
      ST_Transform(
        ST_SetSRID( ST_MakePoint(-89.402945, 43.075688), 4326), 
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
          ST_SetSRID(ST_MakePoint(-89.402945, 43.075688), 4326),
          900913
        ),
        200 -- Circle radius in meters
      ),
      way
    )
  GROUP BY name, way
) t 


--GROUP BY name, point
GROUP BY name
ORDER BY left_heading
;
