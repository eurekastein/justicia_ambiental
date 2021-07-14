-- Primero es necesario pasar la información de las calles a los puntos de la topología de Red
-- Calcular la topología de la red de INEGI 

alter table red_inegi add column source integer;
alter table  red_inegi add column target integer;

 select pgr_createTopology ('red_inegi', 0.01, 'geom', 'id');
 
-- Esto va a generar un archivo con el nombre de la red_vertices_pgr de tipo punto, ahora es necesario intersectar esa red con la topología para pasar los atributos de banquetas etc. 

create table nodos_inegi as
select a.id,a.banqueta, a.arbolado, a.rampas, 
a.alumbrado, a.puestosemi, a.comerciosd, b.the_geom 
from calles a
join calles_vertices_pgr b 
on st_intersects(a.geom, b.the_geom);


-- Trasladar los puntos de los nodos de la red de inegi a la red de OSM

create table nodos_inegi_osm as
SELECT a.id,a.banqueta, a.arbolado, a.rampas,
		a.alumbrado, a.puestosemi, a.comerciosd, 
		ST_LineLocatePoint(edg.the_geom, a.the_geom) AS int_val,
       	ST_ClosestPoint(edg.the_geom, a.the_geom) AS geom
FROM nodos_inegi AS a
JOIN LATERAL (
  SELECT gid,
         the_geom
  FROM ways edg
  ORDER BY a.the_geom <-> edg.the_geom
  LIMIT 1
) AS edg ON true;

---------- Pasar los datos de los puntos trasladados a la red de OSM y crear una nueva red con ambos datos 

create table ways_inegi as
select  a.id,a.banqueta, a.arbolado, a.rampas, a.alumbrado, a.puestosemi, a.comerciosd, b.*
from nodos_inegi_osm a
join ways b 
on st_intersects(a.geom, b.the_geom);


------ Crear el modelo de costos 
-- Calcular la longitud en km 
alter table ways_inegi_tonala add column longitud float; 
update ways_inegi_tonala set longitud = st_length(the_geom)/1000;

-- Calcular velocidad caminando
alter table ways_inegi_tonala add column velocidad float; 
update ways_inegi_tonala set velocidad = longitud/4;

--Modelo de costos incluyendo varialbes de infraestructura
alter table ways_inegi_tonala add column costo float; 

update ways_inegi_tonala set costo =
  case
    when banqueta = 1 then velocidad*0.8
    when arbolado = 1 then velocidad*0.5
    when rampas = 1 then velocidad*0.5
    when alumbrado = 1 then velocidad*0.5
    else velocidad*10
  end;

---- Hacer modelo de costo agregado de traslado 

SELECT DISTINCT ON (start_vid)
       start_vid, end_vid, agg_cost
FROM   (SELECT * FROM pgr_dijkstraCost(
    'select gid as id, source, target, costo as cost from ways_inegi',
    array(select id from ways_vertices_pgr ), 10,
	 directed:=false)
) as sub
ORDER  BY start_vid, agg_cost asc;

