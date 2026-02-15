DELETE FROM  finfadm.urm_menu_tbl where menu_id='CPOPAY';

INSERT INTO finfadm.urm_menu_tbl(menu_id, comp_id, comp_ver, menu_type, is_widget, ubs_menu_id)
VALUES('CPOPAY', 'CO', '10.2', 'UC', 'N', NULL);

insert into finfadm.urm_menu_desc_tbl(menu_id, comp_id, comp_ver, lang_code, menu_desc, menu_tag) 
 values ('CPOPAY','CO','10.2','INFENG','Custom menu for PO Payments','')
on conflict(menu_id, comp_id, comp_ver, lang_code)
do update set 
menu_desc = excluded.menu_desc,
menu_tag = excluded.menu_tag;


insert into finfadm.urm_role_menu_tbl(role_id, entity_id, menu_id, comp_id, comp_ver, access_count, ts_cnt) 
 values('MASTER_ROLE','01','CPOPAY','CO','10.2',1,0)
 on conflict(
    ROLE_ID,
    ENTITY_ID,
    MENU_ID,
    COMP_ID,
    COMP_VER
 )
 do nothing;
 
 delete from tbaadm.menu_option_defn_table where mop_id='CPOPAY';
INSERT INTO tbaadm.menu_option_defn_table
(mop_id,entity_cre_flg,del_flg,mop_type,exe_name,input_filename,additional_params,db_status,mop_term_class_1,
mop_term_class_2,mop_term_class_3,mop_term_class_4,mop_term_class_5,mop_term_class_6,mop_term_class_7,
mop_term_class_8,mop_term_class_9,mop_term_class_10,mop_menu_param,mop_menu_secu_ind,mop_acpt_passwd_flg,
mop_term_type,mop_execution_type,node_type,log_operation_flg,mod_tenor,lchg_user_id,
rcre_user_id,lchg_time,rcre_time,ts_cnt,work_class,template_details,bank_id)
VALUES('CPOPAY','Y','N','U','https://$W/finbranch/','Customize/Customize_ctrl.jsp?sessionid=$S',
       '&sectok=$T&finsessionid=$S&fabsessionid=$C&mo=CPOPAY','F','BT','TT','FT','MT','','','','','','','FINW','M','N','','','','','F',
       'UBSROOT','UBSROOT',SYSDATE,SYSDATE,0,'001 26999N','','01');
	   
delete from tbaadm.MOD_TXT where mop_id='CPOPAY';

INSERT INTO tbaadm.MOD_TXT (MOP_ID,LANG_CODE,USER_MOP_ID,MOP_TEXT,MOP_HELP_TEXT,ENTITY_CRE_FLG,LCHG_USER_ID,RCRE_USER_ID,LCHG_TIME,RCRE_TIME,TS_CNT,BANK_ID)
VALUES('CPOPAY','INFENG','CPOPAY','Custom menu for adding accounts','','Y','UBSADMIN','UBSADMIN',SYSDATE,SYSDATE,0,'01');

delete from tbaadm.MNO where mop_id='CPOPAY';
INSERT INTO tbaadm.MNO (MENU_ID,MOP_NUM,MOP_ID,ENTITY_CRE_FLG,MENU_TYPE,LCHG_USER_ID,LCHG_TIME,RCRE_USER_ID,RCRE_TIME,TS_CNT,BANK_ID)
VALUES('G1B12A1','36','CPOPAY','Y','U','UBSADMIN',SYSDATE,'UBSADMIN',SYSDATE,0,'01');

delete from tbaadm.OAT where mop_id='CPOPAY';
INSERT INTO tbaadm.OAT (MOP_ID,APPL_ID,LCHG_USER_ID,LCHG_TIME,RCRE_USER_ID,RCRE_TIME,TS_CNT,BANK_ID)
VALUES('CPOPAY','G1','UBSADMIN',SYSDATE,'UBSADMIN',SYSDATE,0,'01');