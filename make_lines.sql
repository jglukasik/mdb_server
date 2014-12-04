-- Little script to show how much faster (66x!) it is if we make these lines
-- with pure sql using a numbers table vs procedurally looping with PL/pgSQL
CREATE OR REPLACE 
  FUNCTION make_lines(max_degree integer) 
  RETURNS table(line text, degree_step integer) AS
$$
BEGIN
FOR degree_step IN 0..max_degree LOOP
  RETURN QUERY
    SELECT ST_AsText(ST_Project(ST_MakePoint(0,0), 10, radians(degree_step))), degree_step;
END LOOP;
RETURN;
END
$$
LANGUAGE 'plpgsql';


SELECT s.line AS sline, p.line AS pline, p.degree_step AS deg
FROM make_lines(359) p
FULL JOIN 
  (SELECT 
    ST_AsText(ST_Project(ST_MakePoint(0,0), 10, radians(n.num))) AS line 
   FROM 
    (SELECT num FROM number_table LIMIT 360) n
  ) s
  ON (s.line = p.line)
WHERE s.line IS NULL OR p.line IS NULL;


SELECT count(*) as PLpgSQL FROM make_lines(359);
SELECT 
  count(ST_AsText(ST_Project(ST_MakePoint(0,0), 10, radians(n.num)))) as SQL
FROM 
  (SELECT num FROM number_table LIMIT 360) n;
 
