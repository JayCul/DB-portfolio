-- Deeva's Designs: names for the rows the Portfolio 3 scenarios work on
--
-- Each query stores its result in a psql variable, so the scenarios can
-- write :velvet in place of a material_id. run_scenarios.py loads this
-- file into both sessions. To follow a scenario by hand, run setup.sql
-- once, then load this file in each terminal:
--   \i session_vars.sql

SELECT material_id AS velvet   FROM material WHERE name = 'Royal blue velvet'   \gset
SELECT material_id AS lining   FROM material WHERE name = 'Silver satin lining' \gset
SELECT staff_id    AS staff    FROM staff    WHERE phone = '08000000002'        \gset
SELECT customer_id AS customer FROM customer WHERE phone = '08000000202'        \gset
