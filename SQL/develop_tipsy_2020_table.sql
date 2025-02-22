---TIPSY Development Curves
----------------------------

--remove the output not needed
alter table tipsy_prov_2020 drop stand1;
alter table tipsy_prov_2020 drop stand2;
alter table tipsy_current_prov_2020 drop stand1;
alter table tipsy_current_prov_2020 drop stand2;
--add in eca, dec-pcnt
alter table tipsy_prov_2020 add column eca double precision;
alter table tipsy_prov_2020 add column dec_pcnt double precision;
alter table tipsy_current_prov_2020 add column eca double precision;
alter table tipsy_current_prov_2020 add column dec_pcnt double precision;
--- Deciduous percentage.*/
update tipsy_prov_2020 set dec_pcnt = vol_dec/tvol where tvol > 0 and dec_pcnt > 0;
update tipsy_current_prov_2020 set dec_pcnt = vol_dec/tvol where tvol > 0 and dec_pcnt > 0;

--- format percentages to two decimals;
update tipsy_prov_2020 set dec_pcnt = ROUND(CAST(dec_pcnt as numeric), 2);
update tipsy_prov_2020 set height = ROUND(CAST(height as numeric), 2);
update tipsy_prov_2020 set tvol = ROUND(CAST(tvol as numeric), 2);

update tipsy_current_prov_2020 set dec_pcnt = ROUND(CAST(dec_pcnt as numeric), 2);
update tipsy_current_prov_2020 set height = ROUND(CAST(height as numeric), 2);
update tipsy_current_prov_2020 set tvol = ROUND(CAST(tvol as numeric), 2);

/*STEP 8. Assign ECA. See https://www.for.gov.bc.ca/tasb/legsregs/fpc/FPCGUIDE/wap/WAPGdbk-Web.pdf*/
---Table A2.2 Hydrological recovery for fully stocked stands that reach a maximum crown closure of 50%–70%.
/*Average height of the main canopy (m) % Recovery
0 – <3 0
3 – <5 25
5 – <7 50
7 – <9 75
9 + 90
*/
--ECA = A*(1-R). All VDYP curves are on 0 eca. TIPSY Curves will get this designation.
update tipsy_prov_2020 set eca = 1 where height < 3;
update tipsy_prov_2020 set eca = 0.75 where height >= 3 and height < 5;
update tipsy_prov_2020 set eca = 0.5 where height >= 5 and height < 7;
update tipsy_prov_2020 set eca = 0.25 where height >= 7 and height < 9;
update tipsy_prov_2020 set eca = 0.1 where height >= 9;

update tipsy_current_prov_2020 set eca = 1 where height < 3;
update tipsy_current_prov_2020 set eca = 0.75 where height >= 3 and height < 5;
update tipsy_current_prov_2020 set eca = 0.5 where height >= 5 and height < 7;
update tipsy_current_prov_2020 set eca = 0.25 where height >= 7 and height < 9;
update tipsy_current_prov_2020 set eca = 0.1 where height >= 9;
--- Add in ycgrp********************************************
alter table tipsy_prov_2020 rename column feature_id to ycid; 
Update tipsy_prov_2020 set tvol = 0 where tvol is NULL;
alter table tipsy_prov_2020 rename column crown_closure to crownclosure; 
alter table tipsy_prov_2020 rename column basal_area to basalarea; 

alter table tipsy_current_prov_2020 rename column feature_id to ycid; 
update tipsy_current_prov_2020 set ycid = ycid*-1;

CREATE INDEX IF NOT EXISTS idx_tipsy_current_prov_2020_ycid
    ON public.tipsy_current_prov_2020 USING btree
    (ycid ASC NULLS LAST)
    TABLESPACE pg_default;
	
Update tipsy_current_prov_2020 set tvol = 0 where tvol is NULL;
alter table tipsy_current_prov_2020 rename column crown_closure to crownclosure; 
alter table tipsy_current_prov_2020 rename column basal_area to basalarea; 




