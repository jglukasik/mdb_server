-- This function takes the results from getBuildings, and then corrects the
-- error found when a building straddles the north heading, as our max/min 
-- calculations do not accurately return left/right points in that case
CREATE OR REPLACE
FUNCTION getBuildingsFixed(lng double precision, lat double precision, distance double precision) 
RETURNS setof record AS
$$
DECLARE
  myRow record;
  modified record;
BEGIN
  FOR myRow IN SELECT * FROM getBuildings(lng, lat, distance) g LEFT JOIN planet_osm_polygon p ON g.bName = p.name LOOP
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
  , myRow.way)
THEN
-- Find the correct left- and right-most points
    CREATE TEMP TABLE subquery 
    ON COMMIT DROP
    AS 
    SELECT
      myRow.name,
      ST_AsText(ST_Transform((ST_DumpPoints(myRow.way)).geom, 4326)) AS point,
      -- Find the modified heading by taking (head + 180) % 360, to get accurate min/max without the issues occuring near 0
      mod(cast(degrees(ST_Azimuth(
        ST_Transform(
          ST_SetSRID( ST_MakePoint(lng, lat), 4326), 
          900913
        ),
        (ST_DumpPoints(myRow.way)).geom
      )) as numeric) + 180, 360) AS mod_heading,
      DEGREES(ST_Azimuth(
        ST_Transform(
          ST_SetSRID( ST_MakePoint(-89.402343, 43.075171), 4326), 
          900913
        ),
        (ST_DumpPoints(myRow.way)).geom
      )) AS heading;
 
  SELECT l.name, l.left_point, l.left_heading, r.right_point, r.right_heading
  FROM (
    SELECT
      s1.name,
      s1.point AS left_point,
      s1.heading AS left_heading
    FROM subquery s1
      JOIN subquery s2 on (s1.name = s2.name)
    GROUP BY s1.name, s1.point, s1.heading, s1.mod_heading
    HAVING s1.mod_heading = MIN(s2.mod_heading)
  ) l
  LEFT JOIN (
    SELECT
      s3.name,
      s3.point AS right_point,
      s3.heading AS right_heading
    FROM subquery s3
      JOIN subquery s2 on (s3.name = s2.name)
    GROUP BY s3.name, s3.point, s3.heading, s3.mod_heading
    HAVING s3.mod_heading = MAX(s2.mod_heading)
  ) r
  ON l.name = r.name
  INTO modified;

  myRow.lpoint = modified.left_point;
  myRow.lhead = modified.left_heading;
  myRow.rpoint = modified.right_point;
  myRow.rhead = modified.right_heading;

  RETURN NEXT (myRow.name, myRow.lpoint, myRow.lhead, myRow.rpoint, myRow.rhead);
ELSE
  RETURN NEXT (myRow.name, myRow.lpoint, myRow.lhead, myRow.rpoint, myRow.rhead);
END IF;
END LOOP;
END
$$
LANGUAGE 'plpgsql';

-- Returns all buildings, along with their left/rightmost points and headings,
-- that are found within a 'distance' radius of the 'lnt, lat' provided.
-- Note, this returns incorrect left/rights if the building straddles the 0 
-- degree north heading. This is corrected in getBuildingsFixed, which performs
-- another query on top of this fucntion's results
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

-- Does a degree-by-degree sweep, returning the first building seen at each 
-- degree step.
CREATE OR REPLACE 
  FUNCTION buildingSweep(lng double precision, lat double precision, distance double precision) 
  RETURNS table(building_name text, heading integer) AS
$BODY$
BEGIN
  -- Doing this loop in 5 degree steps greatly improves speed of query, 
  -- I think the tradeoff is worth it, as this will only miss buildings taking
  -- up less than 5 degrees of the users field of view
FOR degree_step IN 0..359 by 5 LOOP
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

-- This function takes our building query, that returns all buildings with
-- left/rightmost points in a certain radius, joined with a building sweep, 
-- which gives first building seen in degree increments. This is a hack to 
-- return only the buildings that are in the users view.

-- TODO: This is slow, becuase buildingSweep is slow with the LOOP from 1 to 
--       360. This can be made faster... Make a row of 1-360, find intersects
--       with all those headings at once, instead of looping?
CREATE OR REPLACE 
  FUNCTION buildingsInView(lng double precision, lat double precision, distance double precision) 
  RETURNS table(bName text, lPoint text, lHead double precision, rPoint text, rHead double precision) AS
$BODY$
BEGIN
  RETURN QUERY
  SELECT b.bName, b.lpoint, b.lhead, b.rpoint, b.rhead
  FROM 
    (SELECT DISTINCT building_name FROM buildingSweep(lng, lat, distance)) s
  INNER JOIN
    (SELECT * FROM getBuildingsFixed(lng, lat, distance) t(bName text, lPoint text, lHead double precision, rPoint text, rHead double precision) ) b
  ON s.building_name = b.bName;
RETURN;
END
$BODY$
LANGUAGE 'plpgsql';
  
