-- KNOTS --------------------------------------------------------------------------------------------------------------
--
-- Knots are used to store finite sets of values, normally used to describe states
-- of entities (through knotted attributes) or relationships (through knotted ties).
-- Knots have their own surrogate identities and are therefore immutable.
-- Values can be added to the set over time though.
-- Knots should have values that are mutually exclusive and exhaustive.
-- Knots are unfolded when using equivalence.
--
-- Knot table ---------------------------------------------------------------------------------------------------------
-- COT_ContainerType table
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."COT_ContainerType" (
    "COT_ID" tinyint not null,
    "COT_ContainerType" varchar(42) not null,
    constraint "pkCOT_ContainerType" primary key (
        "COT_ID"
    ) RELY,
    constraint "uqCOT_ContainerType" unique (
        "COT_ContainerType"
    ) RELY
) CLUSTER BY ("COT_ID");
-- Knot table ---------------------------------------------------------------------------------------------------------
-- CFT_ConfigurationType table
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."CFT_ConfigurationType" (
    "CFT_ID" tinyint not null,
    "CFT_ConfigurationType" varchar(42) not null,
    constraint "pkCFT_ConfigurationType" primary key (
        "CFT_ID"
    ) RELY,
    constraint "uqCFT_ConfigurationType" unique (
        "CFT_ConfigurationType"
    ) RELY
) CLUSTER BY ("CFT_ID");
-- Knot table ---------------------------------------------------------------------------------------------------------
-- TKN_TaskName table
-----------------------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS metadata."TKN_TaskName_ID_SEQ" START 1 INCREMENT 1;
CREATE TABLE IF NOT EXISTS metadata."TKN_TaskName" (
    "TKN_ID" int default metadata."TKN_TaskName_ID_SEQ".nextval not null, 
    "TKN_TaskName" varchar(500) not null,
    constraint "pkTKN_TaskName" primary key (
        "TKN_ID"
    ) RELY,
    constraint "uqTKN_TaskName" unique (
        "TKN_TaskName"
    ) RELY
) CLUSTER BY ("TKN_ID");
-- Knot table ---------------------------------------------------------------------------------------------------------
-- GRG_GraphRunGroupId table
-----------------------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS metadata."GRG_GraphRunGroupId_ID_SEQ" START 1 INCREMENT 1;
CREATE TABLE IF NOT EXISTS metadata."GRG_GraphRunGroupId" (
    "GRG_ID" int default metadata."GRG_GraphRunGroupId_ID_SEQ".nextval not null, 
    "GRG_GraphRunGroupId" varchar(100) not null,
    constraint "pkGRG_GraphRunGroupId" primary key (
        "GRG_ID"
    ) RELY,
    constraint "uqGRG_GraphRunGroupId" unique (
        "GRG_GraphRunGroupId"
    ) RELY
) CLUSTER BY ("GRG_ID");
-- Knot table ---------------------------------------------------------------------------------------------------------
-- ILS_InstallationStatus table
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."ILS_InstallationStatus" (
    "ILS_ID" tinyint not null,
    "ILS_InstallationStatus" varchar(42) not null,
    constraint "pkILS_InstallationStatus" primary key (
        "ILS_ID"
    ) RELY,
    constraint "uqILS_InstallationStatus" unique (
        "ILS_InstallationStatus"
    ) RELY
) CLUSTER BY ("ILS_ID");
-- Knot table ---------------------------------------------------------------------------------------------------------
-- TRS_TaskRunStatus table
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."TRS_TaskRunStatus" (
    "TRS_ID" tinyint not null,
    "TRS_TaskRunStatus" varchar(42) not null,
    constraint "pkTRS_TaskRunStatus" primary key (
        "TRS_ID"
    ) RELY,
    constraint "uqTRS_TaskRunStatus" unique (
        "TRS_TaskRunStatus"
    ) RELY
) CLUSTER BY ("TRS_ID");
-- ANCHORS ------------------------------------------------------------------------------------------------------------
--
-- Anchors are used to store the identities of entities.
-- Anchors are immutable.
--
-- Anchor table -------------------------------------------------------------------------------------------------------
-- TR_TaskRun table (with 6 attributes)
-----------------------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS metadata."TR_TaskRun_ID_SEQ" START 1 INCREMENT 1;
CREATE TABLE IF NOT EXISTS metadata."TR_TaskRun" (
    "TR_ID" int default metadata."TR_TaskRun_ID_SEQ".nextval not null, 
    constraint "pkTR_TaskRun" primary key (
        "TR_ID"
    ) RELY
) CLUSTER BY ("TR_ID");
-- Anchor table -------------------------------------------------------------------------------------------------------
-- CO_Container table (with 3 attributes)
-----------------------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS metadata."CO_Container_ID_SEQ" START 1 INCREMENT 1;
CREATE TABLE IF NOT EXISTS metadata."CO_Container" (
    "CO_ID" int default metadata."CO_Container_ID_SEQ".nextval not null, 
    constraint "pkCO_Container" primary key (
        "CO_ID"
    ) RELY
) CLUSTER BY ("CO_ID");
-- Anchor table -------------------------------------------------------------------------------------------------------
-- CF_Configuration table (with 3 attributes)
-----------------------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS metadata."CF_Configuration_ID_SEQ" START 1 INCREMENT 1;
CREATE TABLE IF NOT EXISTS metadata."CF_Configuration" (
    "CF_ID" int default metadata."CF_Configuration_ID_SEQ".nextval not null, 
    constraint "pkCF_Configuration" primary key (
        "CF_ID"
    ) RELY
) CLUSTER BY ("CF_ID");
-- Anchor table -------------------------------------------------------------------------------------------------------
-- TP_Template table (with 2 attributes)
-----------------------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS metadata."TP_Template_ID_SEQ" START 1 INCREMENT 1;
CREATE TABLE IF NOT EXISTS metadata."TP_Template" (
    "TP_ID" int default metadata."TP_Template_ID_SEQ".nextval not null, 
    constraint "pkTP_Template" primary key (
        "TP_ID"
    ) RELY
) CLUSTER BY ("TP_ID");
-- Anchor table -------------------------------------------------------------------------------------------------------
-- OP_Operations table (with 4 attributes)
-----------------------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS metadata."OP_Operations_ID_SEQ" START 1 INCREMENT 1;
CREATE TABLE IF NOT EXISTS metadata."OP_Operations" (
    "OP_ID" int default metadata."OP_Operations_ID_SEQ".nextval not null, 
    constraint "pkOP_Operations" primary key (
        "OP_ID"
    ) RELY
) CLUSTER BY ("OP_ID");
-- Anchor table -------------------------------------------------------------------------------------------------------
-- IL_Installation table (with 5 attributes)
-----------------------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS metadata."IL_Installation_ID_SEQ" START 1 INCREMENT 1;
CREATE TABLE IF NOT EXISTS metadata."IL_Installation" (
    "IL_ID" int default metadata."IL_Installation_ID_SEQ".nextval not null, 
    constraint "pkIL_Installation" primary key (
        "IL_ID"
    ) RELY
) CLUSTER BY ("IL_ID");
-- NEXUSES ------------------------------------------------------------------------------------------------------------
--
-- Nexuses are used to store identities for event-like entities.
-- Nexuses are immutable.
--
-- ATTRIBUTES ---------------------------------------------------------------------------------------------------------
--
-- Attributes are mutable properties on anchors or nexuses.
-- Attributes have four flavors: static, historized, knotted static, and knotted historized.
--
-- Knotted static attribute table -------------------------------------------------------------------------------------
-- TR_NAM_TaskRun_TaskName table (on TR_TaskRun)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."TR_NAM_TaskRun_TaskName" (
    "TR_NAM_TR_ID" int not null,
    "TR_NAM_TKN_ID" int not null,
    constraint "fk_A_TR_NAM_TaskRun_TaskName" foreign key (
        "TR_NAM_TR_ID"
    ) references metadata."TR_TaskRun"("TR_ID") RELY,
    constraint "fk_K_TR_NAM_TaskRun_TaskName" foreign key (
        "TR_NAM_TKN_ID"
    ) references metadata."TKN_TaskName"("TKN_ID") RELY,
    constraint "pkTR_NAM_TaskRun_TaskName" primary key (
        "TR_NAM_TR_ID"
    ) RELY
) CLUSTER BY ("TR_NAM_TR_ID");
-- Knotted static attribute table -------------------------------------------------------------------------------------
-- TR_GRG_TaskRun_GraphRunGroupId table (on TR_TaskRun)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."TR_GRG_TaskRun_GraphRunGroupId" (
    "TR_GRG_TR_ID" int not null,
    "TR_GRG_GRG_ID" int not null,
    constraint "fk_A_TR_GRG_TaskRun_GraphRunGroupId" foreign key (
        "TR_GRG_TR_ID"
    ) references metadata."TR_TaskRun"("TR_ID") RELY,
    constraint "fk_K_TR_GRG_TaskRun_GraphRunGroupId" foreign key (
        "TR_GRG_GRG_ID"
    ) references metadata."GRG_GraphRunGroupId"("GRG_ID") RELY,
    constraint "pkTR_GRG_TaskRun_GraphRunGroupId" primary key (
        "TR_GRG_TR_ID"
    ) RELY
) CLUSTER BY ("TR_GRG_TR_ID");
-- Static attribute table ---------------------------------------------------------------------------------------------
-- TR_BEG_TaskRun_StartedAt table (on TR_TaskRun)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."TR_BEG_TaskRun_StartedAt" (
    "TR_BEG_TR_ID" int not null,
    "TR_BEG_TaskRun_StartedAt" timestamp_tz not null,
    constraint "fkTR_BEG_TaskRun_StartedAt" foreign key (
        "TR_BEG_TR_ID"
    ) references metadata."TR_TaskRun"("TR_ID") RELY,
    constraint "pkTR_BEG_TaskRun_StartedAt" primary key (
        "TR_BEG_TR_ID"
    ) RELY
) CLUSTER BY ("TR_BEG_TR_ID");
-- Static attribute table ---------------------------------------------------------------------------------------------
-- TR_FIN_TaskRun_FinishedAt table (on TR_TaskRun)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."TR_FIN_TaskRun_FinishedAt" (
    "TR_FIN_TR_ID" int not null,
    "TR_FIN_TaskRun_FinishedAt" timestamp_tz not null,
    constraint "fkTR_FIN_TaskRun_FinishedAt" foreign key (
        "TR_FIN_TR_ID"
    ) references metadata."TR_TaskRun"("TR_ID") RELY,
    constraint "pkTR_FIN_TaskRun_FinishedAt" primary key (
        "TR_FIN_TR_ID"
    ) RELY
) CLUSTER BY ("TR_FIN_TR_ID");
-- Knotted static attribute table -------------------------------------------------------------------------------------
-- TR_STA_TaskRun_Status table (on TR_TaskRun)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."TR_STA_TaskRun_Status" (
    "TR_STA_TR_ID" int not null,
    "TR_STA_TRS_ID" tinyint not null,
    constraint "fk_A_TR_STA_TaskRun_Status" foreign key (
        "TR_STA_TR_ID"
    ) references metadata."TR_TaskRun"("TR_ID") RELY,
    constraint "fk_K_TR_STA_TaskRun_Status" foreign key (
        "TR_STA_TRS_ID"
    ) references metadata."TRS_TaskRunStatus"("TRS_ID") RELY,
    constraint "pkTR_STA_TaskRun_Status" primary key (
        "TR_STA_TR_ID"
    ) RELY
) CLUSTER BY ("TR_STA_TR_ID");
-- Static attribute table ---------------------------------------------------------------------------------------------
-- TR_ERR_TaskRun_Error table (on TR_TaskRun)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."TR_ERR_TaskRun_Error" (
    "TR_ERR_TR_ID" int not null,
    "TR_ERR_TaskRun_Error" varchar(2000) not null,
    constraint "fkTR_ERR_TaskRun_Error" foreign key (
        "TR_ERR_TR_ID"
    ) references metadata."TR_TaskRun"("TR_ID") RELY,
    constraint "pkTR_ERR_TaskRun_Error" primary key (
        "TR_ERR_TR_ID"
    ) RELY
) CLUSTER BY ("TR_ERR_TR_ID");
-- Static attribute table ---------------------------------------------------------------------------------------------
-- CO_NAM_Container_Name table (on CO_Container)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."CO_NAM_Container_Name" (
    "CO_NAM_CO_ID" int not null,
    "CO_NAM_Container_Name" varchar(2000) not null,
    constraint "fkCO_NAM_Container_Name" foreign key (
        "CO_NAM_CO_ID"
    ) references metadata."CO_Container"("CO_ID") RELY,
    constraint "pkCO_NAM_Container_Name" primary key (
        "CO_NAM_CO_ID"
    ) RELY
) CLUSTER BY ("CO_NAM_CO_ID");
-- Knotted static attribute table -------------------------------------------------------------------------------------
-- CO_TYP_Container_Type table (on CO_Container)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."CO_TYP_Container_Type" (
    "CO_TYP_CO_ID" int not null,
    "CO_TYP_COT_ID" tinyint not null,
    constraint "fk_A_CO_TYP_Container_Type" foreign key (
        "CO_TYP_CO_ID"
    ) references metadata."CO_Container"("CO_ID") RELY,
    constraint "fk_K_CO_TYP_Container_Type" foreign key (
        "CO_TYP_COT_ID"
    ) references metadata."COT_ContainerType"("COT_ID") RELY,
    constraint "pkCO_TYP_Container_Type" primary key (
        "CO_TYP_CO_ID"
    ) RELY
) CLUSTER BY ("CO_TYP_CO_ID");
-- Historized attribute table -----------------------------------------------------------------------------------------
-- CO_DSC_Container_Discovered table (on CO_Container)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."CO_DSC_Container_Discovered" (
    "CO_DSC_CO_ID" int not null,
    "CO_DSC_Container_Discovered" timestamp_tz not null,
    "CO_DSC_ChangedAt" timestamp_tz not null,
    constraint "fkCO_DSC_Container_Discovered" foreign key (
        "CO_DSC_CO_ID"
    ) references metadata."CO_Container"("CO_ID") RELY,
    constraint "pkCO_DSC_Container_Discovered" primary key (
        "CO_DSC_CO_ID",
        "CO_DSC_ChangedAt"
    ) RELY
) CLUSTER BY ("CO_DSC_CO_ID");
-- Static attribute table ---------------------------------------------------------------------------------------------
-- CF_NAM_Configuration_Name table (on CF_Configuration)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."CF_NAM_Configuration_Name" (
    "CF_NAM_CF_ID" int not null,
    "CF_NAM_Configuration_Name" varchar(255) not null,
    constraint "fkCF_NAM_Configuration_Name" foreign key (
        "CF_NAM_CF_ID"
    ) references metadata."CF_Configuration"("CF_ID") RELY,
    constraint "pkCF_NAM_Configuration_Name" primary key (
        "CF_NAM_CF_ID"
    ) RELY
) CLUSTER BY ("CF_NAM_CF_ID");
-- Historized attribute table -----------------------------------------------------------------------------------------
-- CF_CNT_Configuration_Content table (on CF_Configuration)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."CF_CNT_Configuration_Content" (
    "CF_CNT_CF_ID" int not null,
    "CF_CNT_Configuration_Content" varchar(16777216) not null,
    "CF_CNT_Checksum" numeric(19,0) default hash("CF_CNT_Configuration_Content"),
    "CF_CNT_ChangedAt" timestamp_tz not null,
    constraint "fkCF_CNT_Configuration_Content" foreign key (
        "CF_CNT_CF_ID"
    ) references metadata."CF_Configuration"("CF_ID") RELY,
    constraint "pkCF_CNT_Configuration_Content" primary key (
        "CF_CNT_CF_ID",
        "CF_CNT_ChangedAt"
    ) RELY
) CLUSTER BY ("CF_CNT_CF_ID");
-- Knotted static attribute table -------------------------------------------------------------------------------------
-- CF_TYP_Configuration_Type table (on CF_Configuration)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."CF_TYP_Configuration_Type" (
    "CF_TYP_CF_ID" int not null,
    "CF_TYP_CFT_ID" tinyint not null,
    constraint "fk_A_CF_TYP_Configuration_Type" foreign key (
        "CF_TYP_CF_ID"
    ) references metadata."CF_Configuration"("CF_ID") RELY,
    constraint "fk_K_CF_TYP_Configuration_Type" foreign key (
        "CF_TYP_CFT_ID"
    ) references metadata."CFT_ConfigurationType"("CFT_ID") RELY,
    constraint "pkCF_TYP_Configuration_Type" primary key (
        "CF_TYP_CF_ID"
    ) RELY
) CLUSTER BY ("CF_TYP_CF_ID");
-- Static attribute table ---------------------------------------------------------------------------------------------
-- TP_NAM_Template_Name table (on TP_Template)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."TP_NAM_Template_Name" (
    "TP_NAM_TP_ID" int not null,
    "TP_NAM_Template_Name" varchar(255) not null,
    constraint "fkTP_NAM_Template_Name" foreign key (
        "TP_NAM_TP_ID"
    ) references metadata."TP_Template"("TP_ID") RELY,
    constraint "pkTP_NAM_Template_Name" primary key (
        "TP_NAM_TP_ID"
    ) RELY
) CLUSTER BY ("TP_NAM_TP_ID");
-- Historized attribute table -----------------------------------------------------------------------------------------
-- TP_CNT_Template_Content table (on TP_Template)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."TP_CNT_Template_Content" (
    "TP_CNT_TP_ID" int not null,
    "TP_CNT_Template_Content" varchar(16777216) not null,
    "TP_CNT_Checksum" numeric(19,0) default hash("TP_CNT_Template_Content"),
    "TP_CNT_ChangedAt" timestamp_tz not null,
    constraint "fkTP_CNT_Template_Content" foreign key (
        "TP_CNT_TP_ID"
    ) references metadata."TP_Template"("TP_ID") RELY,
    constraint "pkTP_CNT_Template_Content" primary key (
        "TP_CNT_TP_ID",
        "TP_CNT_ChangedAt"
    ) RELY
) CLUSTER BY ("TP_CNT_TP_ID");
-- Historized attribute table -----------------------------------------------------------------------------------------
-- OP_INS_Operations_RowsInserted table (on OP_Operations)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."OP_INS_Operations_RowsInserted" (
    "OP_INS_OP_ID" int not null,
    "OP_INS_Operations_RowsInserted" int not null,
    "OP_INS_ChangedAt" timestamp_tz not null,
    constraint "fkOP_INS_Operations_RowsInserted" foreign key (
        "OP_INS_OP_ID"
    ) references metadata."OP_Operations"("OP_ID") RELY,
    constraint "pkOP_INS_Operations_RowsInserted" primary key (
        "OP_INS_OP_ID",
        "OP_INS_ChangedAt"
    ) RELY
) CLUSTER BY ("OP_INS_OP_ID");
-- Historized attribute table -----------------------------------------------------------------------------------------
-- OP_UPD_Operations_RowsUpdated table (on OP_Operations)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."OP_UPD_Operations_RowsUpdated" (
    "OP_UPD_OP_ID" int not null,
    "OP_UPD_Operations_RowsUpdated" int not null,
    "OP_UPD_ChangedAt" timestamp_tz not null,
    constraint "fkOP_UPD_Operations_RowsUpdated" foreign key (
        "OP_UPD_OP_ID"
    ) references metadata."OP_Operations"("OP_ID") RELY,
    constraint "pkOP_UPD_Operations_RowsUpdated" primary key (
        "OP_UPD_OP_ID",
        "OP_UPD_ChangedAt"
    ) RELY
) CLUSTER BY ("OP_UPD_OP_ID");
-- Historized attribute table -----------------------------------------------------------------------------------------
-- OP_DEL_Operations_RowsDeleted table (on OP_Operations)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."OP_DEL_Operations_RowsDeleted" (
    "OP_DEL_OP_ID" int not null,
    "OP_DEL_Operations_RowsDeleted" int not null,
    "OP_DEL_ChangedAt" timestamp_tz not null,
    constraint "fkOP_DEL_Operations_RowsDeleted" foreign key (
        "OP_DEL_OP_ID"
    ) references metadata."OP_Operations"("OP_ID") RELY,
    constraint "pkOP_DEL_Operations_RowsDeleted" primary key (
        "OP_DEL_OP_ID",
        "OP_DEL_ChangedAt"
    ) RELY
) CLUSTER BY ("OP_DEL_OP_ID");
-- Historized attribute table -----------------------------------------------------------------------------------------
-- OP_MRG_Operations_RowsMerged table (on OP_Operations)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."OP_MRG_Operations_RowsMerged" (
    "OP_MRG_OP_ID" int not null,
    "OP_MRG_Operations_RowsMerged" int not null,
    "OP_MRG_ChangedAt" timestamp_tz not null,
    constraint "fkOP_MRG_Operations_RowsMerged" foreign key (
        "OP_MRG_OP_ID"
    ) references metadata."OP_Operations"("OP_ID") RELY,
    constraint "pkOP_MRG_Operations_RowsMerged" primary key (
        "OP_MRG_OP_ID",
        "OP_MRG_ChangedAt"
    ) RELY
) CLUSTER BY ("OP_MRG_OP_ID");
-- Static attribute table ---------------------------------------------------------------------------------------------
-- IL_RID_Installation_RunId table (on IL_Installation)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."IL_RID_Installation_RunId" (
    "IL_RID_IL_ID" int not null,
    "IL_RID_Installation_RunId" varchar(36) not null,
    constraint "fkIL_RID_Installation_RunId" foreign key (
        "IL_RID_IL_ID"
    ) references metadata."IL_Installation"("IL_ID") RELY,
    constraint "pkIL_RID_Installation_RunId" primary key (
        "IL_RID_IL_ID"
    ) RELY
) CLUSTER BY ("IL_RID_IL_ID");
-- Static attribute table ---------------------------------------------------------------------------------------------
-- IL_DDL_Installation_RenderedSql table (on IL_Installation)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."IL_DDL_Installation_RenderedSql" (
    "IL_DDL_IL_ID" int not null,
    "IL_DDL_Installation_RenderedSql" varchar(16777216) not null,
    "IL_DDL_Checksum" numeric(19,0) default hash("IL_DDL_Installation_RenderedSql"),
    constraint "fkIL_DDL_Installation_RenderedSql" foreign key (
        "IL_DDL_IL_ID"
    ) references metadata."IL_Installation"("IL_ID") RELY,
    constraint "pkIL_DDL_Installation_RenderedSql" primary key (
        "IL_DDL_IL_ID"
    ) RELY
) CLUSTER BY ("IL_DDL_IL_ID");
-- Static attribute table ---------------------------------------------------------------------------------------------
-- IL_RAT_Installation_RenderedAt table (on IL_Installation)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."IL_RAT_Installation_RenderedAt" (
    "IL_RAT_IL_ID" int not null,
    "IL_RAT_Installation_RenderedAt" timestamp_tz not null,
    constraint "fkIL_RAT_Installation_RenderedAt" foreign key (
        "IL_RAT_IL_ID"
    ) references metadata."IL_Installation"("IL_ID") RELY,
    constraint "pkIL_RAT_Installation_RenderedAt" primary key (
        "IL_RAT_IL_ID"
    ) RELY
) CLUSTER BY ("IL_RAT_IL_ID");
-- Knotted static attribute table -------------------------------------------------------------------------------------
-- IL_STA_Installation_Status table (on IL_Installation)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."IL_STA_Installation_Status" (
    "IL_STA_IL_ID" int not null,
    "IL_STA_ILS_ID" tinyint not null,
    constraint "fk_A_IL_STA_Installation_Status" foreign key (
        "IL_STA_IL_ID"
    ) references metadata."IL_Installation"("IL_ID") RELY,
    constraint "fk_K_IL_STA_Installation_Status" foreign key (
        "IL_STA_ILS_ID"
    ) references metadata."ILS_InstallationStatus"("ILS_ID") RELY,
    constraint "pkIL_STA_Installation_Status" primary key (
        "IL_STA_IL_ID"
    ) RELY
) CLUSTER BY ("IL_STA_IL_ID");
-- Static attribute table ---------------------------------------------------------------------------------------------
-- IL_ERR_Installation_Error table (on IL_Installation)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."IL_ERR_Installation_Error" (
    "IL_ERR_IL_ID" int not null,
    "IL_ERR_Installation_Error" varchar(2000) not null,
    constraint "fkIL_ERR_Installation_Error" foreign key (
        "IL_ERR_IL_ID"
    ) references metadata."IL_Installation"("IL_ID") RELY,
    constraint "pkIL_ERR_Installation_Error" primary key (
        "IL_ERR_IL_ID"
    ) RELY
) CLUSTER BY ("IL_ERR_IL_ID");
-- TIES ---------------------------------------------------------------------------------------------------------------
--
-- Ties are used to represent relationships between entities.
-- They come in four flavors: static, historized, knotted static, and knotted historized.
-- Ties have cardinality, constraining how members may participate in the relationship.
-- Every entity that is a member in a tie has a specified role in the relationship.
-- Ties must have at least two anchor roles and zero or more knot roles.
--
-- Static tie table ---------------------------------------------------------------------------------------------------
-- TR_operates_CO_source_CO_target_OP_with table (having 4 roles)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."TR_operates_CO_source_CO_target_OP_with" (
    "TR_ID_operates" int not null, 
    "CO_ID_source" int not null, 
    "CO_ID_target" int not null, 
    "OP_ID_with" int not null, 
    constraint "TR_operates_CO_source_CO_target_OP_with_fkTR_operates" foreign key (
        "TR_ID_operates"
    ) references metadata."TR_TaskRun"("TR_ID") RELY, 
    constraint "TR_operates_CO_source_CO_target_OP_with_fkCO_source" foreign key (
        "CO_ID_source"
    ) references metadata."CO_Container"("CO_ID") RELY, 
    constraint "TR_operates_CO_source_CO_target_OP_with_fkCO_target" foreign key (
        "CO_ID_target"
    ) references metadata."CO_Container"("CO_ID") RELY, 
    constraint "TR_operates_CO_source_CO_target_OP_with_fkOP_with" foreign key (
        "OP_ID_with"
    ) references metadata."OP_Operations"("OP_ID") RELY, 
    constraint "pkTR_operates_CO_source_CO_target_OP_with" primary key (
        "TR_ID_operates",
        "CO_ID_source",
        "CO_ID_target"
    ) RELY
) CLUSTER BY (
    "TR_ID_operates",
    "CO_ID_source",
    "CO_ID_target",
    "OP_ID_with"
);
-- Static tie table ---------------------------------------------------------------------------------------------------
-- TR_formed_CF_from table (having 2 roles)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."TR_formed_CF_from" (
    "TR_ID_formed" int not null, 
    "CF_ID_from" int not null, 
    constraint "TR_formed_CF_from_fkTR_formed" foreign key (
        "TR_ID_formed"
    ) references metadata."TR_TaskRun"("TR_ID") RELY, 
    constraint "TR_formed_CF_from_fkCF_from" foreign key (
        "CF_ID_from"
    ) references metadata."CF_Configuration"("CF_ID") RELY, 
    constraint "pkTR_formed_CF_from" primary key (
        "TR_ID_formed"
    ) RELY
) CLUSTER BY (
    "TR_ID_formed",
    "CF_ID_from"
);
-- Static tie table ---------------------------------------------------------------------------------------------------
-- CF_uses_TP_template table (having 2 roles)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."CF_uses_TP_template" (
    "CF_ID_uses" int not null, 
    "TP_ID_template" int not null, 
    constraint "CF_uses_TP_template_fkCF_uses" foreign key (
        "CF_ID_uses"
    ) references metadata."CF_Configuration"("CF_ID") RELY, 
    constraint "CF_uses_TP_template_fkTP_template" foreign key (
        "TP_ID_template"
    ) references metadata."TP_Template"("TP_ID") RELY, 
    constraint "pkCF_uses_TP_template" primary key (
        "CF_ID_uses"
    ) RELY
) CLUSTER BY (
    "CF_ID_uses",
    "TP_ID_template"
);
-- Static tie table ---------------------------------------------------------------------------------------------------
-- IL_installs_CF_configuration table (having 2 roles)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."IL_installs_CF_configuration" (
    "IL_ID_installs" int not null, 
    "CF_ID_configuration" int not null, 
    constraint "IL_installs_CF_configuration_fkIL_installs" foreign key (
        "IL_ID_installs"
    ) references metadata."IL_Installation"("IL_ID") RELY, 
    constraint "IL_installs_CF_configuration_fkCF_configuration" foreign key (
        "CF_ID_configuration"
    ) references metadata."CF_Configuration"("CF_ID") RELY, 
    constraint "pkIL_installs_CF_configuration" primary key (
        "IL_ID_installs"
    ) RELY
) CLUSTER BY (
    "IL_ID_installs",
    "CF_ID_configuration"
);
-- Static tie table ---------------------------------------------------------------------------------------------------
-- IL_applies_TP_rendered table (having 2 roles)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata."IL_applies_TP_rendered" (
    "IL_ID_applies" int not null, 
    "TP_ID_rendered" int not null, 
    constraint "IL_applies_TP_rendered_fkIL_applies" foreign key (
        "IL_ID_applies"
    ) references metadata."IL_Installation"("IL_ID") RELY, 
    constraint "IL_applies_TP_rendered_fkTP_rendered" foreign key (
        "TP_ID_rendered"
    ) references metadata."TP_Template"("TP_ID") RELY, 
    constraint "pkIL_applies_TP_rendered" primary key (
        "IL_ID_applies"
    ) RELY
) CLUSTER BY (
    "IL_ID_applies",
    "TP_ID_rendered"
);
-- KNOT EQUIVALENCE VIEWS ---------------------------------------------------------------------------------------------
--
-- Equivalence views combine the identity and equivalent parts of a knot into a single view, making
-- it look and behave like a regular knot. They also make it possible to retrieve data for only the
-- given equivalent.
--
-- @equivalent the equivalent that you want to retrieve data for
--
-- ATTRIBUTE EQUIVALENCE VIEWS ----------------------------------------------------------------------------------------
--
-- Equivalence views of attributes make it possible to retrieve data for only the given equivalent.
--
-- @equivalent the equivalent that you want to retrieve data for
--
-- ATTRIBUTE REWINDERS ------------------------------------------------------------------------------------------------
--
-- These table valued functions rewind an attribute table to the given
-- point in changing time. It does not pick a temporal perspective and
-- instead shows all rows that have been in effect before that point
-- in time.
--
-- @changingTimepoint the point in changing time to rewind to
--
-- Attribute rewinder -------------------------------------------------------------------------------------------------
-- rCO_DSC_Container_Discovered rewinding over changing time function
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata."rCO_DSC_Container_Discovered" (
    changingTimepoint timestamp_tz
)
COPY GRANTS
RETURNS TABLE (
    "CO_DSC_CO_ID" int,
    "CO_DSC_Container_Discovered" timestamp_tz,
    "CO_DSC_ChangedAt" timestamp_tz
)
AS
$$
    SELECT
        "CO_DSC_CO_ID",
        "CO_DSC_Container_Discovered",
        "CO_DSC_ChangedAt"
    FROM
        metadata."CO_DSC_Container_Discovered"
    WHERE
        "CO_DSC_ChangedAt" <= changingTimepoint
$$
;
-- Attribute rewinder -------------------------------------------------------------------------------------------------
-- rCF_CNT_Configuration_Content rewinding over changing time function
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata."rCF_CNT_Configuration_Content" (
    changingTimepoint timestamp_tz
)
COPY GRANTS
RETURNS TABLE (
    "CF_CNT_CF_ID" int,
    "CF_CNT_Checksum" numeric(19,0),
    "CF_CNT_Configuration_Content" varchar(16777216),
    "CF_CNT_ChangedAt" timestamp_tz
)
AS
$$
    SELECT
        "CF_CNT_CF_ID",
        "CF_CNT_Checksum",
        "CF_CNT_Configuration_Content",
        "CF_CNT_ChangedAt"
    FROM
        metadata."CF_CNT_Configuration_Content"
    WHERE
        "CF_CNT_ChangedAt" <= changingTimepoint
$$
;
-- Attribute rewinder -------------------------------------------------------------------------------------------------
-- rTP_CNT_Template_Content rewinding over changing time function
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata."rTP_CNT_Template_Content" (
    changingTimepoint timestamp_tz
)
COPY GRANTS
RETURNS TABLE (
    "TP_CNT_TP_ID" int,
    "TP_CNT_Checksum" numeric(19,0),
    "TP_CNT_Template_Content" varchar(16777216),
    "TP_CNT_ChangedAt" timestamp_tz
)
AS
$$
    SELECT
        "TP_CNT_TP_ID",
        "TP_CNT_Checksum",
        "TP_CNT_Template_Content",
        "TP_CNT_ChangedAt"
    FROM
        metadata."TP_CNT_Template_Content"
    WHERE
        "TP_CNT_ChangedAt" <= changingTimepoint
$$
;
-- Attribute rewinder -------------------------------------------------------------------------------------------------
-- rOP_INS_Operations_RowsInserted rewinding over changing time function
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata."rOP_INS_Operations_RowsInserted" (
    changingTimepoint timestamp_tz
)
COPY GRANTS
RETURNS TABLE (
    "OP_INS_OP_ID" int,
    "OP_INS_Operations_RowsInserted" int,
    "OP_INS_ChangedAt" timestamp_tz
)
AS
$$
    SELECT
        "OP_INS_OP_ID",
        "OP_INS_Operations_RowsInserted",
        "OP_INS_ChangedAt"
    FROM
        metadata."OP_INS_Operations_RowsInserted"
    WHERE
        "OP_INS_ChangedAt" <= changingTimepoint
$$
;
-- Attribute rewinder -------------------------------------------------------------------------------------------------
-- rOP_UPD_Operations_RowsUpdated rewinding over changing time function
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata."rOP_UPD_Operations_RowsUpdated" (
    changingTimepoint timestamp_tz
)
COPY GRANTS
RETURNS TABLE (
    "OP_UPD_OP_ID" int,
    "OP_UPD_Operations_RowsUpdated" int,
    "OP_UPD_ChangedAt" timestamp_tz
)
AS
$$
    SELECT
        "OP_UPD_OP_ID",
        "OP_UPD_Operations_RowsUpdated",
        "OP_UPD_ChangedAt"
    FROM
        metadata."OP_UPD_Operations_RowsUpdated"
    WHERE
        "OP_UPD_ChangedAt" <= changingTimepoint
$$
;
-- Attribute rewinder -------------------------------------------------------------------------------------------------
-- rOP_DEL_Operations_RowsDeleted rewinding over changing time function
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata."rOP_DEL_Operations_RowsDeleted" (
    changingTimepoint timestamp_tz
)
COPY GRANTS
RETURNS TABLE (
    "OP_DEL_OP_ID" int,
    "OP_DEL_Operations_RowsDeleted" int,
    "OP_DEL_ChangedAt" timestamp_tz
)
AS
$$
    SELECT
        "OP_DEL_OP_ID",
        "OP_DEL_Operations_RowsDeleted",
        "OP_DEL_ChangedAt"
    FROM
        metadata."OP_DEL_Operations_RowsDeleted"
    WHERE
        "OP_DEL_ChangedAt" <= changingTimepoint
$$
;
-- Attribute rewinder -------------------------------------------------------------------------------------------------
-- rOP_MRG_Operations_RowsMerged rewinding over changing time function
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata."rOP_MRG_Operations_RowsMerged" (
    changingTimepoint timestamp_tz
)
COPY GRANTS
RETURNS TABLE (
    "OP_MRG_OP_ID" int,
    "OP_MRG_Operations_RowsMerged" int,
    "OP_MRG_ChangedAt" timestamp_tz
)
AS
$$
    SELECT
        "OP_MRG_OP_ID",
        "OP_MRG_Operations_RowsMerged",
        "OP_MRG_ChangedAt"
    FROM
        metadata."OP_MRG_Operations_RowsMerged"
    WHERE
        "OP_MRG_ChangedAt" <= changingTimepoint
$$
;
-- ANCHOR TEMPORAL PERSPECTIVES ---------------------------------------------------------------------------------------
--
-- Snowflake-native anchor perspectives: latest (l), point-in-time (p), now (n), difference (d),
-- and their equivalence variants (el, ep, en, ed).
--
-- Latest perspective -------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."lTR_TaskRun" (
    "TR_ID",
    "TR_NAM_TR_ID",
    "TR_NAM_TKN_TaskName",
    "TR_NAM_TKN_ID",
    "TR_GRG_TR_ID",
    "TR_GRG_GRG_GraphRunGroupId",
    "TR_GRG_GRG_ID",
    "TR_BEG_TR_ID",
    "TR_BEG_TaskRun_StartedAt",
    "TR_FIN_TR_ID",
    "TR_FIN_TaskRun_FinishedAt",
    "TR_STA_TR_ID",
    "TR_STA_TRS_TaskRunStatus",
    "TR_STA_TRS_ID",
    "TR_ERR_TR_ID",
    "TR_ERR_TaskRun_Error"
) COPY GRANTS 
AS
SELECT
    "TR"."TR_ID",
    "NAM"."TR_NAM_TR_ID",
    "kNAM"."TKN_TaskName" AS "TR_NAM_TKN_TaskName",
    "NAM"."TR_NAM_TKN_ID",
    "GRG"."TR_GRG_TR_ID",
    "kGRG"."GRG_GraphRunGroupId" AS "TR_GRG_GRG_GraphRunGroupId",
    "GRG"."TR_GRG_GRG_ID",
    "BEG"."TR_BEG_TR_ID",
    "BEG"."TR_BEG_TaskRun_StartedAt",
    "FIN"."TR_FIN_TR_ID",
    "FIN"."TR_FIN_TaskRun_FinishedAt",
    "STA"."TR_STA_TR_ID",
    "kSTA"."TRS_TaskRunStatus" AS "TR_STA_TRS_TaskRunStatus",
    "STA"."TR_STA_TRS_ID",
    "ERR"."TR_ERR_TR_ID",
    "ERR"."TR_ERR_TaskRun_Error"
FROM
    metadata."TR_TaskRun" "TR"
LEFT JOIN
    metadata."TR_NAM_TaskRun_TaskName" "NAM"
ON
    "NAM"."TR_NAM_TR_ID" = "TR"."TR_ID"
LEFT JOIN
    metadata."TKN_TaskName" "kNAM"
ON
    "kNAM"."TKN_ID" = "NAM"."TR_NAM_TKN_ID"
LEFT JOIN
    metadata."TR_GRG_TaskRun_GraphRunGroupId" "GRG"
ON
    "GRG"."TR_GRG_TR_ID" = "TR"."TR_ID"
LEFT JOIN
    metadata."GRG_GraphRunGroupId" "kGRG"
ON
    "kGRG"."GRG_ID" = "GRG"."TR_GRG_GRG_ID"
LEFT JOIN
    metadata."TR_BEG_TaskRun_StartedAt" "BEG"
ON
    "BEG"."TR_BEG_TR_ID" = "TR"."TR_ID"
LEFT JOIN
    metadata."TR_FIN_TaskRun_FinishedAt" "FIN"
ON
    "FIN"."TR_FIN_TR_ID" = "TR"."TR_ID"
LEFT JOIN
    metadata."TR_STA_TaskRun_Status" "STA"
ON
    "STA"."TR_STA_TR_ID" = "TR"."TR_ID"
LEFT JOIN
    metadata."TRS_TaskRunStatus" "kSTA"
ON
    "kSTA"."TRS_ID" = "STA"."TR_STA_TRS_ID"
LEFT JOIN
    metadata."TR_ERR_TaskRun_Error" "ERR"
ON
    "ERR"."TR_ERR_TR_ID" = "TR"."TR_ID";
-- Point-in-time perspective ------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata."pTR_TaskRun" (
    changingTimepoint timestamp_tz
)
COPY GRANTS
RETURNS TABLE (
    "TR_ID" int,
    "TR_NAM_TR_ID" int,
    "TR_NAM_TKN_TaskName" varchar(500),
    "TR_NAM_TKN_ID" int,
    "TR_GRG_TR_ID" int,
    "TR_GRG_GRG_GraphRunGroupId" varchar(100),
    "TR_GRG_GRG_ID" int,
    "TR_BEG_TR_ID" int,
    "TR_BEG_TaskRun_StartedAt" timestamp_tz,
    "TR_FIN_TR_ID" int,
    "TR_FIN_TaskRun_FinishedAt" timestamp_tz,
    "TR_STA_TR_ID" int,
    "TR_STA_TRS_TaskRunStatus" varchar(42),
    "TR_STA_TRS_ID" tinyint,
    "TR_ERR_TR_ID" int,
    "TR_ERR_TaskRun_Error" varchar(2000)
)
AS
$$
SELECT
    "TR"."TR_ID",
    "NAM"."TR_NAM_TR_ID",
    "kNAM"."TKN_TaskName" AS "TR_NAM_TKN_TaskName",
    "NAM"."TR_NAM_TKN_ID",
    "GRG"."TR_GRG_TR_ID",
    "kGRG"."GRG_GraphRunGroupId" AS "TR_GRG_GRG_GraphRunGroupId",
    "GRG"."TR_GRG_GRG_ID",
    "BEG"."TR_BEG_TR_ID",
    "BEG"."TR_BEG_TaskRun_StartedAt",
    "FIN"."TR_FIN_TR_ID",
    "FIN"."TR_FIN_TaskRun_FinishedAt",
    "STA"."TR_STA_TR_ID",
    "kSTA"."TRS_TaskRunStatus" AS "TR_STA_TRS_TaskRunStatus",
    "STA"."TR_STA_TRS_ID",
    "ERR"."TR_ERR_TR_ID",
    "ERR"."TR_ERR_TaskRun_Error"
FROM
    metadata."TR_TaskRun" "TR"
LEFT JOIN
    metadata."TR_NAM_TaskRun_TaskName" "NAM"
ON
    "NAM"."TR_NAM_TR_ID" = "TR"."TR_ID"
LEFT JOIN
    metadata."TKN_TaskName" "kNAM"
ON
    "kNAM"."TKN_ID" = "NAM"."TR_NAM_TKN_ID"
LEFT JOIN
    metadata."TR_GRG_TaskRun_GraphRunGroupId" "GRG"
ON
    "GRG"."TR_GRG_TR_ID" = "TR"."TR_ID"
LEFT JOIN
    metadata."GRG_GraphRunGroupId" "kGRG"
ON
    "kGRG"."GRG_ID" = "GRG"."TR_GRG_GRG_ID"
LEFT JOIN
    metadata."TR_BEG_TaskRun_StartedAt" "BEG"
ON
    "BEG"."TR_BEG_TR_ID" = "TR"."TR_ID"
LEFT JOIN
    metadata."TR_FIN_TaskRun_FinishedAt" "FIN"
ON
    "FIN"."TR_FIN_TR_ID" = "TR"."TR_ID"
LEFT JOIN
    metadata."TR_STA_TaskRun_Status" "STA"
ON
    "STA"."TR_STA_TR_ID" = "TR"."TR_ID"
LEFT JOIN
    metadata."TRS_TaskRunStatus" "kSTA"
ON
    "kSTA"."TRS_ID" = "STA"."TR_STA_TRS_ID"
LEFT JOIN
    metadata."TR_ERR_TaskRun_Error" "ERR"
ON
    "ERR"."TR_ERR_TR_ID" = "TR"."TR_ID"
$$
;
-- Now perspective ----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."nTR_TaskRun" COPY GRANTS
AS
SELECT
    *
FROM
    TABLE(metadata."pTR_TaskRun"(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)::timestamp_tz))
;
-- Latest perspective -------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."lCO_Container" (
    "CO_ID",
    "CO_NAM_CO_ID",
    "CO_NAM_Container_Name",
    "CO_TYP_CO_ID",
    "CO_TYP_COT_ContainerType",
    "CO_TYP_COT_ID",
    "CO_DSC_CO_ID",
    "CO_DSC_ChangedAt",
    "CO_DSC_Container_Discovered"
) COPY GRANTS 
AS
SELECT
    "CO"."CO_ID",
    "NAM"."CO_NAM_CO_ID",
    "NAM"."CO_NAM_Container_Name",
    "TYP"."CO_TYP_CO_ID",
    "kTYP"."COT_ContainerType" AS "CO_TYP_COT_ContainerType",
    "TYP"."CO_TYP_COT_ID",
    "DSC"."CO_DSC_CO_ID",
    "DSC"."CO_DSC_ChangedAt",
    "DSC"."CO_DSC_Container_Discovered"
FROM
    metadata."CO_Container" "CO"
LEFT JOIN
    metadata."CO_NAM_Container_Name" "NAM"
ON
    "NAM"."CO_NAM_CO_ID" = "CO"."CO_ID"
LEFT JOIN
    metadata."CO_TYP_Container_Type" "TYP"
ON
    "TYP"."CO_TYP_CO_ID" = "CO"."CO_ID"
LEFT JOIN
    metadata."COT_ContainerType" "kTYP"
ON
    "kTYP"."COT_ID" = "TYP"."CO_TYP_COT_ID"
LEFT JOIN
    metadata."CO_DSC_Container_Discovered" "DSC"
ON
    "DSC"."CO_DSC_CO_ID" = "CO"."CO_ID"
AND
    "DSC"."CO_DSC_ChangedAt" = (
        SELECT
            max(sub."CO_DSC_ChangedAt")
        FROM
            metadata."CO_DSC_Container_Discovered" sub
        WHERE
            sub."CO_DSC_CO_ID" = "CO"."CO_ID"
   );
-- Point-in-time perspective ------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata."pCO_Container" (
    changingTimepoint timestamp_tz
)
COPY GRANTS
RETURNS TABLE (
    "CO_ID" int,
    "CO_NAM_CO_ID" int,
    "CO_NAM_Container_Name" varchar(2000),
    "CO_TYP_CO_ID" int,
    "CO_TYP_COT_ContainerType" varchar(42),
    "CO_TYP_COT_ID" tinyint,
    "CO_DSC_CO_ID" int,
    "CO_DSC_ChangedAt" timestamp_tz,
    "CO_DSC_Container_Discovered" timestamp_tz
)
AS
$$
SELECT
    "CO"."CO_ID",
    "NAM"."CO_NAM_CO_ID",
    "NAM"."CO_NAM_Container_Name",
    "TYP"."CO_TYP_CO_ID",
    "kTYP"."COT_ContainerType" AS "CO_TYP_COT_ContainerType",
    "TYP"."CO_TYP_COT_ID",
    "DSC"."CO_DSC_CO_ID",
    "DSC"."CO_DSC_ChangedAt",
    "DSC"."CO_DSC_Container_Discovered"
FROM
    metadata."CO_Container" "CO"
LEFT JOIN
    metadata."CO_NAM_Container_Name" "NAM"
ON
    "NAM"."CO_NAM_CO_ID" = "CO"."CO_ID"
LEFT JOIN
    metadata."CO_TYP_Container_Type" "TYP"
ON
    "TYP"."CO_TYP_CO_ID" = "CO"."CO_ID"
LEFT JOIN
    metadata."COT_ContainerType" "kTYP"
ON
    "kTYP"."COT_ID" = "TYP"."CO_TYP_COT_ID"
LEFT JOIN
    TABLE(metadata."rCO_DSC_Container_Discovered"(changingTimepoint::timestamp_tz)) "DSC"
ON
    "DSC"."CO_DSC_CO_ID" = "CO"."CO_ID"
AND
    "DSC"."CO_DSC_ChangedAt" = (
        SELECT
            max(sub."CO_DSC_ChangedAt")
        FROM
            TABLE(metadata."rCO_DSC_Container_Discovered"(changingTimepoint::timestamp_tz)) sub
        WHERE
            sub."CO_DSC_CO_ID" = "CO"."CO_ID"
   )
$$
;
-- Now perspective ----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."nCO_Container" COPY GRANTS
AS
SELECT
    *
FROM
    TABLE(metadata."pCO_Container"(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)::timestamp_tz))
;
-- Difference perspective ---------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata."dCO_Container" (
    intervalStart timestamp_tz,
    intervalEnd timestamp_tz,
    selection string
)
COPY GRANTS
RETURNS TABLE (
    inspectedTimepoint timestamp_tz,
    mnemonic string,
    "CO_ID" int,
    "CO_NAM_CO_ID" int,
    "CO_NAM_Container_Name" varchar(2000),
    "CO_TYP_CO_ID" int,
    "CO_TYP_COT_ContainerType" varchar(42),
    "CO_TYP_COT_ID" tinyint,
    "CO_DSC_CO_ID" int,
    "CO_DSC_ChangedAt" timestamp_tz,
    "CO_DSC_Container_Discovered" timestamp_tz
)
AS
$$
-- each change in the interval, with the values in effect then: every value is joined with the time until which it
-- holds, when the next one does. Snowflake cannot call the point-in-time perspective for each change, since it cannot
-- evaluate a function with an outer join on its argument for each row of another table.
SELECT
    timepoints.inspectedTimepoint,
    timepoints.mnemonic,
    "CO"."CO_ID",
    "NAM"."CO_NAM_CO_ID",
    "NAM"."CO_NAM_Container_Name",
    "TYP"."CO_TYP_CO_ID",
    "kTYP"."COT_ContainerType" AS "CO_TYP_COT_ContainerType",
    "TYP"."CO_TYP_COT_ID",
    "DSC"."CO_DSC_CO_ID",
    "DSC"."CO_DSC_ChangedAt",
    "DSC"."CO_DSC_Container_Discovered"
FROM (
    SELECT DISTINCT
        h."CO_DSC_CO_ID" AS "CO_ID",
        h."CO_DSC_ChangedAt"::timestamp_tz AS inspectedTimepoint,
        'DSC' AS mnemonic
    FROM
        metadata."CO_DSC_Container_Discovered" h
    WHERE
        (selection IS NULL OR selection LIKE '%DSC%')
    AND
        h."CO_DSC_ChangedAt" BETWEEN intervalStart AND intervalEnd
) timepoints
JOIN
    metadata."CO_Container" "CO"
ON
    "CO"."CO_ID" = timepoints."CO_ID"
LEFT JOIN
    metadata."CO_NAM_Container_Name" "NAM"
ON
    "NAM"."CO_NAM_CO_ID" = "CO"."CO_ID"
LEFT JOIN
    metadata."CO_TYP_Container_Type" "TYP"
ON
    "TYP"."CO_TYP_CO_ID" = "CO"."CO_ID"
LEFT JOIN
    metadata."COT_ContainerType" "kTYP"
ON
    "kTYP"."COT_ID" = "TYP"."CO_TYP_COT_ID"
LEFT JOIN (
    SELECT
        h.*,
        lead(h."CO_DSC_ChangedAt") OVER (
            PARTITION BY h."CO_DSC_CO_ID"
            ORDER BY h."CO_DSC_ChangedAt"
        ) AS "until"
    FROM
        metadata."CO_DSC_Container_Discovered" h
) "DSC"
ON
    "DSC"."CO_DSC_CO_ID" = "CO"."CO_ID"
AND
    "DSC"."CO_DSC_ChangedAt" <= timepoints.inspectedTimepoint::timestamp_tz
AND (
    "DSC"."until" IS NULL
OR
    "DSC"."until" > timepoints.inspectedTimepoint::timestamp_tz
)
$$
;
-- Latest perspective -------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."lCF_Configuration" (
    "CF_ID",
    "CF_NAM_CF_ID",
    "CF_NAM_Configuration_Name",
    "CF_CNT_CF_ID",
    "CF_CNT_ChangedAt",
    "CF_CNT_Checksum",
    "CF_CNT_Configuration_Content",
    "CF_TYP_CF_ID",
    "CF_TYP_CFT_ConfigurationType",
    "CF_TYP_CFT_ID"
) COPY GRANTS 
AS
SELECT
    "CF"."CF_ID",
    "NAM"."CF_NAM_CF_ID",
    "NAM"."CF_NAM_Configuration_Name",
    "CNT"."CF_CNT_CF_ID",
    "CNT"."CF_CNT_ChangedAt",
    "CNT"."CF_CNT_Checksum",
    "CNT"."CF_CNT_Configuration_Content",
    "TYP"."CF_TYP_CF_ID",
    "kTYP"."CFT_ConfigurationType" AS "CF_TYP_CFT_ConfigurationType",
    "TYP"."CF_TYP_CFT_ID"
FROM
    metadata."CF_Configuration" "CF"
LEFT JOIN
    metadata."CF_NAM_Configuration_Name" "NAM"
ON
    "NAM"."CF_NAM_CF_ID" = "CF"."CF_ID"
LEFT JOIN
    metadata."CF_CNT_Configuration_Content" "CNT"
ON
    "CNT"."CF_CNT_CF_ID" = "CF"."CF_ID"
AND
    "CNT"."CF_CNT_ChangedAt" = (
        SELECT
            max(sub."CF_CNT_ChangedAt")
        FROM
            metadata."CF_CNT_Configuration_Content" sub
        WHERE
            sub."CF_CNT_CF_ID" = "CF"."CF_ID"
   )
LEFT JOIN
    metadata."CF_TYP_Configuration_Type" "TYP"
ON
    "TYP"."CF_TYP_CF_ID" = "CF"."CF_ID"
LEFT JOIN
    metadata."CFT_ConfigurationType" "kTYP"
ON
    "kTYP"."CFT_ID" = "TYP"."CF_TYP_CFT_ID";
-- Point-in-time perspective ------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata."pCF_Configuration" (
    changingTimepoint timestamp_tz
)
COPY GRANTS
RETURNS TABLE (
    "CF_ID" int,
    "CF_NAM_CF_ID" int,
    "CF_NAM_Configuration_Name" varchar(255),
    "CF_CNT_CF_ID" int,
    "CF_CNT_ChangedAt" timestamp_tz,
    "CF_CNT_Checksum" numeric(19,0),
    "CF_CNT_Configuration_Content" varchar(16777216),
    "CF_TYP_CF_ID" int,
    "CF_TYP_CFT_ConfigurationType" varchar(42),
    "CF_TYP_CFT_ID" tinyint
)
AS
$$
SELECT
    "CF"."CF_ID",
    "NAM"."CF_NAM_CF_ID",
    "NAM"."CF_NAM_Configuration_Name",
    "CNT"."CF_CNT_CF_ID",
    "CNT"."CF_CNT_ChangedAt",
    "CNT"."CF_CNT_Checksum",
    "CNT"."CF_CNT_Configuration_Content",
    "TYP"."CF_TYP_CF_ID",
    "kTYP"."CFT_ConfigurationType" AS "CF_TYP_CFT_ConfigurationType",
    "TYP"."CF_TYP_CFT_ID"
FROM
    metadata."CF_Configuration" "CF"
LEFT JOIN
    metadata."CF_NAM_Configuration_Name" "NAM"
ON
    "NAM"."CF_NAM_CF_ID" = "CF"."CF_ID"
LEFT JOIN
    TABLE(metadata."rCF_CNT_Configuration_Content"(changingTimepoint::timestamp_tz)) "CNT"
ON
    "CNT"."CF_CNT_CF_ID" = "CF"."CF_ID"
AND
    "CNT"."CF_CNT_ChangedAt" = (
        SELECT
            max(sub."CF_CNT_ChangedAt")
        FROM
            TABLE(metadata."rCF_CNT_Configuration_Content"(changingTimepoint::timestamp_tz)) sub
        WHERE
            sub."CF_CNT_CF_ID" = "CF"."CF_ID"
   )
LEFT JOIN
    metadata."CF_TYP_Configuration_Type" "TYP"
ON
    "TYP"."CF_TYP_CF_ID" = "CF"."CF_ID"
LEFT JOIN
    metadata."CFT_ConfigurationType" "kTYP"
ON
    "kTYP"."CFT_ID" = "TYP"."CF_TYP_CFT_ID"
$$
;
-- Now perspective ----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."nCF_Configuration" COPY GRANTS
AS
SELECT
    *
FROM
    TABLE(metadata."pCF_Configuration"(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)::timestamp_tz))
;
-- Difference perspective ---------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata."dCF_Configuration" (
    intervalStart timestamp_tz,
    intervalEnd timestamp_tz,
    selection string
)
COPY GRANTS
RETURNS TABLE (
    inspectedTimepoint timestamp_tz,
    mnemonic string,
    "CF_ID" int,
    "CF_NAM_CF_ID" int,
    "CF_NAM_Configuration_Name" varchar(255),
    "CF_CNT_CF_ID" int,
    "CF_CNT_ChangedAt" timestamp_tz,
    "CF_CNT_Checksum" numeric(19,0),
    "CF_CNT_Configuration_Content" varchar(16777216),
    "CF_TYP_CF_ID" int,
    "CF_TYP_CFT_ConfigurationType" varchar(42),
    "CF_TYP_CFT_ID" tinyint
)
AS
$$
-- each change in the interval, with the values in effect then: every value is joined with the time until which it
-- holds, when the next one does. Snowflake cannot call the point-in-time perspective for each change, since it cannot
-- evaluate a function with an outer join on its argument for each row of another table.
SELECT
    timepoints.inspectedTimepoint,
    timepoints.mnemonic,
    "CF"."CF_ID",
    "NAM"."CF_NAM_CF_ID",
    "NAM"."CF_NAM_Configuration_Name",
    "CNT"."CF_CNT_CF_ID",
    "CNT"."CF_CNT_ChangedAt",
    "CNT"."CF_CNT_Checksum",
    "CNT"."CF_CNT_Configuration_Content",
    "TYP"."CF_TYP_CF_ID",
    "kTYP"."CFT_ConfigurationType" AS "CF_TYP_CFT_ConfigurationType",
    "TYP"."CF_TYP_CFT_ID"
FROM (
    SELECT DISTINCT
        h."CF_CNT_CF_ID" AS "CF_ID",
        h."CF_CNT_ChangedAt"::timestamp_tz AS inspectedTimepoint,
        'CNT' AS mnemonic
    FROM
        metadata."CF_CNT_Configuration_Content" h
    WHERE
        (selection IS NULL OR selection LIKE '%CNT%')
    AND
        h."CF_CNT_ChangedAt" BETWEEN intervalStart AND intervalEnd
) timepoints
JOIN
    metadata."CF_Configuration" "CF"
ON
    "CF"."CF_ID" = timepoints."CF_ID"
LEFT JOIN
    metadata."CF_NAM_Configuration_Name" "NAM"
ON
    "NAM"."CF_NAM_CF_ID" = "CF"."CF_ID"
LEFT JOIN (
    SELECT
        h.*,
        lead(h."CF_CNT_ChangedAt") OVER (
            PARTITION BY h."CF_CNT_CF_ID"
            ORDER BY h."CF_CNT_ChangedAt"
        ) AS "until"
    FROM
        metadata."CF_CNT_Configuration_Content" h
) "CNT"
ON
    "CNT"."CF_CNT_CF_ID" = "CF"."CF_ID"
AND
    "CNT"."CF_CNT_ChangedAt" <= timepoints.inspectedTimepoint::timestamp_tz
AND (
    "CNT"."until" IS NULL
OR
    "CNT"."until" > timepoints.inspectedTimepoint::timestamp_tz
)
LEFT JOIN
    metadata."CF_TYP_Configuration_Type" "TYP"
ON
    "TYP"."CF_TYP_CF_ID" = "CF"."CF_ID"
LEFT JOIN
    metadata."CFT_ConfigurationType" "kTYP"
ON
    "kTYP"."CFT_ID" = "TYP"."CF_TYP_CFT_ID"
$$
;
-- Latest perspective -------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."lTP_Template" (
    "TP_ID",
    "TP_NAM_TP_ID",
    "TP_NAM_Template_Name",
    "TP_CNT_TP_ID",
    "TP_CNT_ChangedAt",
    "TP_CNT_Checksum",
    "TP_CNT_Template_Content"
) COPY GRANTS 
AS
SELECT
    "TP"."TP_ID",
    "NAM"."TP_NAM_TP_ID",
    "NAM"."TP_NAM_Template_Name",
    "CNT"."TP_CNT_TP_ID",
    "CNT"."TP_CNT_ChangedAt",
    "CNT"."TP_CNT_Checksum",
    "CNT"."TP_CNT_Template_Content"
FROM
    metadata."TP_Template" "TP"
LEFT JOIN
    metadata."TP_NAM_Template_Name" "NAM"
ON
    "NAM"."TP_NAM_TP_ID" = "TP"."TP_ID"
LEFT JOIN
    metadata."TP_CNT_Template_Content" "CNT"
ON
    "CNT"."TP_CNT_TP_ID" = "TP"."TP_ID"
AND
    "CNT"."TP_CNT_ChangedAt" = (
        SELECT
            max(sub."TP_CNT_ChangedAt")
        FROM
            metadata."TP_CNT_Template_Content" sub
        WHERE
            sub."TP_CNT_TP_ID" = "TP"."TP_ID"
   );
-- Point-in-time perspective ------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata."pTP_Template" (
    changingTimepoint timestamp_tz
)
COPY GRANTS
RETURNS TABLE (
    "TP_ID" int,
    "TP_NAM_TP_ID" int,
    "TP_NAM_Template_Name" varchar(255),
    "TP_CNT_TP_ID" int,
    "TP_CNT_ChangedAt" timestamp_tz,
    "TP_CNT_Checksum" numeric(19,0),
    "TP_CNT_Template_Content" varchar(16777216)
)
AS
$$
SELECT
    "TP"."TP_ID",
    "NAM"."TP_NAM_TP_ID",
    "NAM"."TP_NAM_Template_Name",
    "CNT"."TP_CNT_TP_ID",
    "CNT"."TP_CNT_ChangedAt",
    "CNT"."TP_CNT_Checksum",
    "CNT"."TP_CNT_Template_Content"
FROM
    metadata."TP_Template" "TP"
LEFT JOIN
    metadata."TP_NAM_Template_Name" "NAM"
ON
    "NAM"."TP_NAM_TP_ID" = "TP"."TP_ID"
LEFT JOIN
    TABLE(metadata."rTP_CNT_Template_Content"(changingTimepoint::timestamp_tz)) "CNT"
ON
    "CNT"."TP_CNT_TP_ID" = "TP"."TP_ID"
AND
    "CNT"."TP_CNT_ChangedAt" = (
        SELECT
            max(sub."TP_CNT_ChangedAt")
        FROM
            TABLE(metadata."rTP_CNT_Template_Content"(changingTimepoint::timestamp_tz)) sub
        WHERE
            sub."TP_CNT_TP_ID" = "TP"."TP_ID"
   )
$$
;
-- Now perspective ----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."nTP_Template" COPY GRANTS
AS
SELECT
    *
FROM
    TABLE(metadata."pTP_Template"(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)::timestamp_tz))
;
-- Difference perspective ---------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata."dTP_Template" (
    intervalStart timestamp_tz,
    intervalEnd timestamp_tz,
    selection string
)
COPY GRANTS
RETURNS TABLE (
    inspectedTimepoint timestamp_tz,
    mnemonic string,
    "TP_ID" int,
    "TP_NAM_TP_ID" int,
    "TP_NAM_Template_Name" varchar(255),
    "TP_CNT_TP_ID" int,
    "TP_CNT_ChangedAt" timestamp_tz,
    "TP_CNT_Checksum" numeric(19,0),
    "TP_CNT_Template_Content" varchar(16777216)
)
AS
$$
-- each change in the interval, with the values in effect then: every value is joined with the time until which it
-- holds, when the next one does. Snowflake cannot call the point-in-time perspective for each change, since it cannot
-- evaluate a function with an outer join on its argument for each row of another table.
SELECT
    timepoints.inspectedTimepoint,
    timepoints.mnemonic,
    "TP"."TP_ID",
    "NAM"."TP_NAM_TP_ID",
    "NAM"."TP_NAM_Template_Name",
    "CNT"."TP_CNT_TP_ID",
    "CNT"."TP_CNT_ChangedAt",
    "CNT"."TP_CNT_Checksum",
    "CNT"."TP_CNT_Template_Content"
FROM (
    SELECT DISTINCT
        h."TP_CNT_TP_ID" AS "TP_ID",
        h."TP_CNT_ChangedAt"::timestamp_tz AS inspectedTimepoint,
        'CNT' AS mnemonic
    FROM
        metadata."TP_CNT_Template_Content" h
    WHERE
        (selection IS NULL OR selection LIKE '%CNT%')
    AND
        h."TP_CNT_ChangedAt" BETWEEN intervalStart AND intervalEnd
) timepoints
JOIN
    metadata."TP_Template" "TP"
ON
    "TP"."TP_ID" = timepoints."TP_ID"
LEFT JOIN
    metadata."TP_NAM_Template_Name" "NAM"
ON
    "NAM"."TP_NAM_TP_ID" = "TP"."TP_ID"
LEFT JOIN (
    SELECT
        h.*,
        lead(h."TP_CNT_ChangedAt") OVER (
            PARTITION BY h."TP_CNT_TP_ID"
            ORDER BY h."TP_CNT_ChangedAt"
        ) AS "until"
    FROM
        metadata."TP_CNT_Template_Content" h
) "CNT"
ON
    "CNT"."TP_CNT_TP_ID" = "TP"."TP_ID"
AND
    "CNT"."TP_CNT_ChangedAt" <= timepoints.inspectedTimepoint::timestamp_tz
AND (
    "CNT"."until" IS NULL
OR
    "CNT"."until" > timepoints.inspectedTimepoint::timestamp_tz
)
$$
;
-- Latest perspective -------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."lOP_Operations" (
    "OP_ID",
    "OP_INS_OP_ID",
    "OP_INS_ChangedAt",
    "OP_INS_Operations_RowsInserted",
    "OP_UPD_OP_ID",
    "OP_UPD_ChangedAt",
    "OP_UPD_Operations_RowsUpdated",
    "OP_DEL_OP_ID",
    "OP_DEL_ChangedAt",
    "OP_DEL_Operations_RowsDeleted",
    "OP_MRG_OP_ID",
    "OP_MRG_ChangedAt",
    "OP_MRG_Operations_RowsMerged"
) COPY GRANTS 
AS
SELECT
    "OP"."OP_ID",
    "INS"."OP_INS_OP_ID",
    "INS"."OP_INS_ChangedAt",
    "INS"."OP_INS_Operations_RowsInserted",
    "UPD"."OP_UPD_OP_ID",
    "UPD"."OP_UPD_ChangedAt",
    "UPD"."OP_UPD_Operations_RowsUpdated",
    "DEL"."OP_DEL_OP_ID",
    "DEL"."OP_DEL_ChangedAt",
    "DEL"."OP_DEL_Operations_RowsDeleted",
    "MRG"."OP_MRG_OP_ID",
    "MRG"."OP_MRG_ChangedAt",
    "MRG"."OP_MRG_Operations_RowsMerged"
FROM
    metadata."OP_Operations" "OP"
LEFT JOIN
    metadata."OP_INS_Operations_RowsInserted" "INS"
ON
    "INS"."OP_INS_OP_ID" = "OP"."OP_ID"
AND
    "INS"."OP_INS_ChangedAt" = (
        SELECT
            max(sub."OP_INS_ChangedAt")
        FROM
            metadata."OP_INS_Operations_RowsInserted" sub
        WHERE
            sub."OP_INS_OP_ID" = "OP"."OP_ID"
   )
LEFT JOIN
    metadata."OP_UPD_Operations_RowsUpdated" "UPD"
ON
    "UPD"."OP_UPD_OP_ID" = "OP"."OP_ID"
AND
    "UPD"."OP_UPD_ChangedAt" = (
        SELECT
            max(sub."OP_UPD_ChangedAt")
        FROM
            metadata."OP_UPD_Operations_RowsUpdated" sub
        WHERE
            sub."OP_UPD_OP_ID" = "OP"."OP_ID"
   )
LEFT JOIN
    metadata."OP_DEL_Operations_RowsDeleted" "DEL"
ON
    "DEL"."OP_DEL_OP_ID" = "OP"."OP_ID"
AND
    "DEL"."OP_DEL_ChangedAt" = (
        SELECT
            max(sub."OP_DEL_ChangedAt")
        FROM
            metadata."OP_DEL_Operations_RowsDeleted" sub
        WHERE
            sub."OP_DEL_OP_ID" = "OP"."OP_ID"
   )
LEFT JOIN
    metadata."OP_MRG_Operations_RowsMerged" "MRG"
ON
    "MRG"."OP_MRG_OP_ID" = "OP"."OP_ID"
AND
    "MRG"."OP_MRG_ChangedAt" = (
        SELECT
            max(sub."OP_MRG_ChangedAt")
        FROM
            metadata."OP_MRG_Operations_RowsMerged" sub
        WHERE
            sub."OP_MRG_OP_ID" = "OP"."OP_ID"
   );
-- Point-in-time perspective ------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata."pOP_Operations" (
    changingTimepoint timestamp_tz
)
COPY GRANTS
RETURNS TABLE (
    "OP_ID" int,
    "OP_INS_OP_ID" int,
    "OP_INS_ChangedAt" timestamp_tz,
    "OP_INS_Operations_RowsInserted" int,
    "OP_UPD_OP_ID" int,
    "OP_UPD_ChangedAt" timestamp_tz,
    "OP_UPD_Operations_RowsUpdated" int,
    "OP_DEL_OP_ID" int,
    "OP_DEL_ChangedAt" timestamp_tz,
    "OP_DEL_Operations_RowsDeleted" int,
    "OP_MRG_OP_ID" int,
    "OP_MRG_ChangedAt" timestamp_tz,
    "OP_MRG_Operations_RowsMerged" int
)
AS
$$
SELECT
    "OP"."OP_ID",
    "INS"."OP_INS_OP_ID",
    "INS"."OP_INS_ChangedAt",
    "INS"."OP_INS_Operations_RowsInserted",
    "UPD"."OP_UPD_OP_ID",
    "UPD"."OP_UPD_ChangedAt",
    "UPD"."OP_UPD_Operations_RowsUpdated",
    "DEL"."OP_DEL_OP_ID",
    "DEL"."OP_DEL_ChangedAt",
    "DEL"."OP_DEL_Operations_RowsDeleted",
    "MRG"."OP_MRG_OP_ID",
    "MRG"."OP_MRG_ChangedAt",
    "MRG"."OP_MRG_Operations_RowsMerged"
FROM
    metadata."OP_Operations" "OP"
LEFT JOIN
    TABLE(metadata."rOP_INS_Operations_RowsInserted"(changingTimepoint::timestamp_tz)) "INS"
ON
    "INS"."OP_INS_OP_ID" = "OP"."OP_ID"
AND
    "INS"."OP_INS_ChangedAt" = (
        SELECT
            max(sub."OP_INS_ChangedAt")
        FROM
            TABLE(metadata."rOP_INS_Operations_RowsInserted"(changingTimepoint::timestamp_tz)) sub
        WHERE
            sub."OP_INS_OP_ID" = "OP"."OP_ID"
   )
LEFT JOIN
    TABLE(metadata."rOP_UPD_Operations_RowsUpdated"(changingTimepoint::timestamp_tz)) "UPD"
ON
    "UPD"."OP_UPD_OP_ID" = "OP"."OP_ID"
AND
    "UPD"."OP_UPD_ChangedAt" = (
        SELECT
            max(sub."OP_UPD_ChangedAt")
        FROM
            TABLE(metadata."rOP_UPD_Operations_RowsUpdated"(changingTimepoint::timestamp_tz)) sub
        WHERE
            sub."OP_UPD_OP_ID" = "OP"."OP_ID"
   )
LEFT JOIN
    TABLE(metadata."rOP_DEL_Operations_RowsDeleted"(changingTimepoint::timestamp_tz)) "DEL"
ON
    "DEL"."OP_DEL_OP_ID" = "OP"."OP_ID"
AND
    "DEL"."OP_DEL_ChangedAt" = (
        SELECT
            max(sub."OP_DEL_ChangedAt")
        FROM
            TABLE(metadata."rOP_DEL_Operations_RowsDeleted"(changingTimepoint::timestamp_tz)) sub
        WHERE
            sub."OP_DEL_OP_ID" = "OP"."OP_ID"
   )
LEFT JOIN
    TABLE(metadata."rOP_MRG_Operations_RowsMerged"(changingTimepoint::timestamp_tz)) "MRG"
ON
    "MRG"."OP_MRG_OP_ID" = "OP"."OP_ID"
AND
    "MRG"."OP_MRG_ChangedAt" = (
        SELECT
            max(sub."OP_MRG_ChangedAt")
        FROM
            TABLE(metadata."rOP_MRG_Operations_RowsMerged"(changingTimepoint::timestamp_tz)) sub
        WHERE
            sub."OP_MRG_OP_ID" = "OP"."OP_ID"
   )
$$
;
-- Now perspective ----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."nOP_Operations" COPY GRANTS
AS
SELECT
    *
FROM
    TABLE(metadata."pOP_Operations"(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)::timestamp_tz))
;
-- Difference perspective ---------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata."dOP_Operations" (
    intervalStart timestamp_tz,
    intervalEnd timestamp_tz,
    selection string
)
COPY GRANTS
RETURNS TABLE (
    inspectedTimepoint timestamp_tz,
    mnemonic string,
    "OP_ID" int,
    "OP_INS_OP_ID" int,
    "OP_INS_ChangedAt" timestamp_tz,
    "OP_INS_Operations_RowsInserted" int,
    "OP_UPD_OP_ID" int,
    "OP_UPD_ChangedAt" timestamp_tz,
    "OP_UPD_Operations_RowsUpdated" int,
    "OP_DEL_OP_ID" int,
    "OP_DEL_ChangedAt" timestamp_tz,
    "OP_DEL_Operations_RowsDeleted" int,
    "OP_MRG_OP_ID" int,
    "OP_MRG_ChangedAt" timestamp_tz,
    "OP_MRG_Operations_RowsMerged" int
)
AS
$$
-- each change in the interval, with the values in effect then: every value is joined with the time until which it
-- holds, when the next one does. Snowflake cannot call the point-in-time perspective for each change, since it cannot
-- evaluate a function with an outer join on its argument for each row of another table.
SELECT
    timepoints.inspectedTimepoint,
    timepoints.mnemonic,
    "OP"."OP_ID",
    "INS"."OP_INS_OP_ID",
    "INS"."OP_INS_ChangedAt",
    "INS"."OP_INS_Operations_RowsInserted",
    "UPD"."OP_UPD_OP_ID",
    "UPD"."OP_UPD_ChangedAt",
    "UPD"."OP_UPD_Operations_RowsUpdated",
    "DEL"."OP_DEL_OP_ID",
    "DEL"."OP_DEL_ChangedAt",
    "DEL"."OP_DEL_Operations_RowsDeleted",
    "MRG"."OP_MRG_OP_ID",
    "MRG"."OP_MRG_ChangedAt",
    "MRG"."OP_MRG_Operations_RowsMerged"
FROM (
    SELECT DISTINCT
        h."OP_INS_OP_ID" AS "OP_ID",
        h."OP_INS_ChangedAt"::timestamp_tz AS inspectedTimepoint,
        'INS' AS mnemonic
    FROM
        metadata."OP_INS_Operations_RowsInserted" h
    WHERE
        (selection IS NULL OR selection LIKE '%INS%')
    AND
        h."OP_INS_ChangedAt" BETWEEN intervalStart AND intervalEnd
    UNION
    SELECT DISTINCT
        h."OP_UPD_OP_ID" AS "OP_ID",
        h."OP_UPD_ChangedAt"::timestamp_tz AS inspectedTimepoint,
        'UPD' AS mnemonic
    FROM
        metadata."OP_UPD_Operations_RowsUpdated" h
    WHERE
        (selection IS NULL OR selection LIKE '%UPD%')
    AND
        h."OP_UPD_ChangedAt" BETWEEN intervalStart AND intervalEnd
    UNION
    SELECT DISTINCT
        h."OP_DEL_OP_ID" AS "OP_ID",
        h."OP_DEL_ChangedAt"::timestamp_tz AS inspectedTimepoint,
        'DEL' AS mnemonic
    FROM
        metadata."OP_DEL_Operations_RowsDeleted" h
    WHERE
        (selection IS NULL OR selection LIKE '%DEL%')
    AND
        h."OP_DEL_ChangedAt" BETWEEN intervalStart AND intervalEnd
    UNION
    SELECT DISTINCT
        h."OP_MRG_OP_ID" AS "OP_ID",
        h."OP_MRG_ChangedAt"::timestamp_tz AS inspectedTimepoint,
        'MRG' AS mnemonic
    FROM
        metadata."OP_MRG_Operations_RowsMerged" h
    WHERE
        (selection IS NULL OR selection LIKE '%MRG%')
    AND
        h."OP_MRG_ChangedAt" BETWEEN intervalStart AND intervalEnd
) timepoints
JOIN
    metadata."OP_Operations" "OP"
ON
    "OP"."OP_ID" = timepoints."OP_ID"
LEFT JOIN (
    SELECT
        h.*,
        lead(h."OP_INS_ChangedAt") OVER (
            PARTITION BY h."OP_INS_OP_ID"
            ORDER BY h."OP_INS_ChangedAt"
        ) AS "until"
    FROM
        metadata."OP_INS_Operations_RowsInserted" h
) "INS"
ON
    "INS"."OP_INS_OP_ID" = "OP"."OP_ID"
AND
    "INS"."OP_INS_ChangedAt" <= timepoints.inspectedTimepoint::timestamp_tz
AND (
    "INS"."until" IS NULL
OR
    "INS"."until" > timepoints.inspectedTimepoint::timestamp_tz
)
LEFT JOIN (
    SELECT
        h.*,
        lead(h."OP_UPD_ChangedAt") OVER (
            PARTITION BY h."OP_UPD_OP_ID"
            ORDER BY h."OP_UPD_ChangedAt"
        ) AS "until"
    FROM
        metadata."OP_UPD_Operations_RowsUpdated" h
) "UPD"
ON
    "UPD"."OP_UPD_OP_ID" = "OP"."OP_ID"
AND
    "UPD"."OP_UPD_ChangedAt" <= timepoints.inspectedTimepoint::timestamp_tz
AND (
    "UPD"."until" IS NULL
OR
    "UPD"."until" > timepoints.inspectedTimepoint::timestamp_tz
)
LEFT JOIN (
    SELECT
        h.*,
        lead(h."OP_DEL_ChangedAt") OVER (
            PARTITION BY h."OP_DEL_OP_ID"
            ORDER BY h."OP_DEL_ChangedAt"
        ) AS "until"
    FROM
        metadata."OP_DEL_Operations_RowsDeleted" h
) "DEL"
ON
    "DEL"."OP_DEL_OP_ID" = "OP"."OP_ID"
AND
    "DEL"."OP_DEL_ChangedAt" <= timepoints.inspectedTimepoint::timestamp_tz
AND (
    "DEL"."until" IS NULL
OR
    "DEL"."until" > timepoints.inspectedTimepoint::timestamp_tz
)
LEFT JOIN (
    SELECT
        h.*,
        lead(h."OP_MRG_ChangedAt") OVER (
            PARTITION BY h."OP_MRG_OP_ID"
            ORDER BY h."OP_MRG_ChangedAt"
        ) AS "until"
    FROM
        metadata."OP_MRG_Operations_RowsMerged" h
) "MRG"
ON
    "MRG"."OP_MRG_OP_ID" = "OP"."OP_ID"
AND
    "MRG"."OP_MRG_ChangedAt" <= timepoints.inspectedTimepoint::timestamp_tz
AND (
    "MRG"."until" IS NULL
OR
    "MRG"."until" > timepoints.inspectedTimepoint::timestamp_tz
)
$$
;
-- Latest perspective -------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."lIL_Installation" (
    "IL_ID",
    "IL_RID_IL_ID",
    "IL_RID_Installation_RunId",
    "IL_DDL_IL_ID",
    "IL_DDL_Checksum",
    "IL_DDL_Installation_RenderedSql",
    "IL_RAT_IL_ID",
    "IL_RAT_Installation_RenderedAt",
    "IL_STA_IL_ID",
    "IL_STA_ILS_InstallationStatus",
    "IL_STA_ILS_ID",
    "IL_ERR_IL_ID",
    "IL_ERR_Installation_Error"
) COPY GRANTS 
AS
SELECT
    "IL"."IL_ID",
    "RID"."IL_RID_IL_ID",
    "RID"."IL_RID_Installation_RunId",
    "DDL"."IL_DDL_IL_ID",
    "DDL"."IL_DDL_Checksum",
    "DDL"."IL_DDL_Installation_RenderedSql",
    "RAT"."IL_RAT_IL_ID",
    "RAT"."IL_RAT_Installation_RenderedAt",
    "STA"."IL_STA_IL_ID",
    "kSTA"."ILS_InstallationStatus" AS "IL_STA_ILS_InstallationStatus",
    "STA"."IL_STA_ILS_ID",
    "ERR"."IL_ERR_IL_ID",
    "ERR"."IL_ERR_Installation_Error"
FROM
    metadata."IL_Installation" "IL"
LEFT JOIN
    metadata."IL_RID_Installation_RunId" "RID"
ON
    "RID"."IL_RID_IL_ID" = "IL"."IL_ID"
LEFT JOIN
    metadata."IL_DDL_Installation_RenderedSql" "DDL"
ON
    "DDL"."IL_DDL_IL_ID" = "IL"."IL_ID"
LEFT JOIN
    metadata."IL_RAT_Installation_RenderedAt" "RAT"
ON
    "RAT"."IL_RAT_IL_ID" = "IL"."IL_ID"
LEFT JOIN
    metadata."IL_STA_Installation_Status" "STA"
ON
    "STA"."IL_STA_IL_ID" = "IL"."IL_ID"
LEFT JOIN
    metadata."ILS_InstallationStatus" "kSTA"
ON
    "kSTA"."ILS_ID" = "STA"."IL_STA_ILS_ID"
LEFT JOIN
    metadata."IL_ERR_Installation_Error" "ERR"
ON
    "ERR"."IL_ERR_IL_ID" = "IL"."IL_ID";
-- Point-in-time perspective ------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata."pIL_Installation" (
    changingTimepoint timestamp_tz
)
COPY GRANTS
RETURNS TABLE (
    "IL_ID" int,
    "IL_RID_IL_ID" int,
    "IL_RID_Installation_RunId" varchar(36),
    "IL_DDL_IL_ID" int,
    "IL_DDL_Checksum" numeric(19,0),
    "IL_DDL_Installation_RenderedSql" varchar(16777216),
    "IL_RAT_IL_ID" int,
    "IL_RAT_Installation_RenderedAt" timestamp_tz,
    "IL_STA_IL_ID" int,
    "IL_STA_ILS_InstallationStatus" varchar(42),
    "IL_STA_ILS_ID" tinyint,
    "IL_ERR_IL_ID" int,
    "IL_ERR_Installation_Error" varchar(2000)
)
AS
$$
SELECT
    "IL"."IL_ID",
    "RID"."IL_RID_IL_ID",
    "RID"."IL_RID_Installation_RunId",
    "DDL"."IL_DDL_IL_ID",
    "DDL"."IL_DDL_Checksum",
    "DDL"."IL_DDL_Installation_RenderedSql",
    "RAT"."IL_RAT_IL_ID",
    "RAT"."IL_RAT_Installation_RenderedAt",
    "STA"."IL_STA_IL_ID",
    "kSTA"."ILS_InstallationStatus" AS "IL_STA_ILS_InstallationStatus",
    "STA"."IL_STA_ILS_ID",
    "ERR"."IL_ERR_IL_ID",
    "ERR"."IL_ERR_Installation_Error"
FROM
    metadata."IL_Installation" "IL"
LEFT JOIN
    metadata."IL_RID_Installation_RunId" "RID"
ON
    "RID"."IL_RID_IL_ID" = "IL"."IL_ID"
LEFT JOIN
    metadata."IL_DDL_Installation_RenderedSql" "DDL"
ON
    "DDL"."IL_DDL_IL_ID" = "IL"."IL_ID"
LEFT JOIN
    metadata."IL_RAT_Installation_RenderedAt" "RAT"
ON
    "RAT"."IL_RAT_IL_ID" = "IL"."IL_ID"
LEFT JOIN
    metadata."IL_STA_Installation_Status" "STA"
ON
    "STA"."IL_STA_IL_ID" = "IL"."IL_ID"
LEFT JOIN
    metadata."ILS_InstallationStatus" "kSTA"
ON
    "kSTA"."ILS_ID" = "STA"."IL_STA_ILS_ID"
LEFT JOIN
    metadata."IL_ERR_Installation_Error" "ERR"
ON
    "ERR"."IL_ERR_IL_ID" = "IL"."IL_ID"
$$
;
-- Now perspective ----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."nIL_Installation" COPY GRANTS
AS
SELECT
    *
FROM
    TABLE(metadata."pIL_Installation"(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)::timestamp_tz))
;
-- NEXUS TEMPORAL PERSPECTIVES ----------------------------------------------------------------------------------------
--
-- Snowflake-native nexus perspectives: latest (l), point-in-time (p), now (n), difference (d),
-- and equivalence variants (el, ep, en, ed).
--
-- TIE TEMPORAL PERSPECTIVES ------------------------------------------------------------------------------------------
--
-- Snowflake-native tie perspectives: latest (l), point-in-time (p), now (n), difference (d),
-- and equivalence variants (el, ep, en, ed).
--
-- Latest perspective -------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."lTR_operates_CO_source_CO_target_OP_with" (
    "TR_ID_operates",
    "CO_ID_source",
    "CO_ID_target",
    "OP_ID_with"
) COPY GRANTS 
AS
SELECT
    tie."TR_ID_operates",
    tie."CO_ID_source",
    tie."CO_ID_target",
    tie."OP_ID_with"
FROM
    metadata."TR_operates_CO_source_CO_target_OP_with" tie
;
-- Point-in-time perspective ------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata."pTR_operates_CO_source_CO_target_OP_with" (
    changingTimepoint timestamp_tz
)
COPY GRANTS
RETURNS TABLE (
    "TR_ID_operates" int,
    "CO_ID_source" int,
    "CO_ID_target" int,
    "OP_ID_with" int
)
AS
$$
SELECT
    tie."TR_ID_operates",
    tie."CO_ID_source",
    tie."CO_ID_target",
    tie."OP_ID_with"
FROM
    metadata."TR_operates_CO_source_CO_target_OP_with" tie
$$
;
-- Now perspective ----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."nTR_operates_CO_source_CO_target_OP_with" COPY GRANTS AS
SELECT
    *
FROM
    TABLE(metadata."pTR_operates_CO_source_CO_target_OP_with"(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)::timestamp_tz))
;
-- Latest perspective -------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."lTR_formed_CF_from" (
    "TR_ID_formed",
    "CF_ID_from"
) COPY GRANTS 
AS
SELECT
    tie."TR_ID_formed",
    tie."CF_ID_from"
FROM
    metadata."TR_formed_CF_from" tie
;
-- Point-in-time perspective ------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata."pTR_formed_CF_from" (
    changingTimepoint timestamp_tz
)
COPY GRANTS
RETURNS TABLE (
    "TR_ID_formed" int,
    "CF_ID_from" int
)
AS
$$
SELECT
    tie."TR_ID_formed",
    tie."CF_ID_from"
FROM
    metadata."TR_formed_CF_from" tie
$$
;
-- Now perspective ----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."nTR_formed_CF_from" COPY GRANTS AS
SELECT
    *
FROM
    TABLE(metadata."pTR_formed_CF_from"(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)::timestamp_tz))
;
-- Latest perspective -------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."lCF_uses_TP_template" (
    "CF_ID_uses",
    "TP_ID_template"
) COPY GRANTS 
AS
SELECT
    tie."CF_ID_uses",
    tie."TP_ID_template"
FROM
    metadata."CF_uses_TP_template" tie
;
-- Point-in-time perspective ------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata."pCF_uses_TP_template" (
    changingTimepoint timestamp_tz
)
COPY GRANTS
RETURNS TABLE (
    "CF_ID_uses" int,
    "TP_ID_template" int
)
AS
$$
SELECT
    tie."CF_ID_uses",
    tie."TP_ID_template"
FROM
    metadata."CF_uses_TP_template" tie
$$
;
-- Now perspective ----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."nCF_uses_TP_template" COPY GRANTS AS
SELECT
    *
FROM
    TABLE(metadata."pCF_uses_TP_template"(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)::timestamp_tz))
;
-- Latest perspective -------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."lIL_installs_CF_configuration" (
    "IL_ID_installs",
    "CF_ID_configuration"
) COPY GRANTS 
AS
SELECT
    tie."IL_ID_installs",
    tie."CF_ID_configuration"
FROM
    metadata."IL_installs_CF_configuration" tie
;
-- Point-in-time perspective ------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata."pIL_installs_CF_configuration" (
    changingTimepoint timestamp_tz
)
COPY GRANTS
RETURNS TABLE (
    "IL_ID_installs" int,
    "CF_ID_configuration" int
)
AS
$$
SELECT
    tie."IL_ID_installs",
    tie."CF_ID_configuration"
FROM
    metadata."IL_installs_CF_configuration" tie
$$
;
-- Now perspective ----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."nIL_installs_CF_configuration" COPY GRANTS AS
SELECT
    *
FROM
    TABLE(metadata."pIL_installs_CF_configuration"(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)::timestamp_tz))
;
-- Latest perspective -------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."lIL_applies_TP_rendered" (
    "IL_ID_applies",
    "TP_ID_rendered"
) COPY GRANTS 
AS
SELECT
    tie."IL_ID_applies",
    tie."TP_ID_rendered"
FROM
    metadata."IL_applies_TP_rendered" tie
;
-- Point-in-time perspective ------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata."pIL_applies_TP_rendered" (
    changingTimepoint timestamp_tz
)
COPY GRANTS
RETURNS TABLE (
    "IL_ID_applies" int,
    "TP_ID_rendered" int
)
AS
$$
SELECT
    tie."IL_ID_applies",
    tie."TP_ID_rendered"
FROM
    metadata."IL_applies_TP_rendered" tie
$$
;
-- Now perspective ----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."nIL_applies_TP_rendered" COPY GRANTS AS
SELECT
    *
FROM
    TABLE(metadata."pIL_applies_TP_rendered"(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)::timestamp_tz))
;
-- INTEGRITY CHECKS ---------------------------------------------------------------------------------------------------
--
-- Snowflake does not enforce primary, unique or foreign keys, and every key here is declared RELY, which tells the
-- optimizer to trust it. A violation is therefore not an error, but wrong results. Every table has a view,
-- ic_<table>, that returns the rows that break what the table declares:
--
--   duplicate primary key, duplicate unique key   the same key more than once
--   no row in <table> for <column>                a reference to a row that does not exist
--   restatement                                   in an attribute or a tie that may not store them, a value
--                                                 that is the same as the one before it in changing time
--
-- A view that returns nothing has nothing wrong. IntegrityViolations is all of them together; it reads every table.
-- It also has the checks of the natural keys, ic_key_<anchor or nexus>_<route>, which are made with the keys: a key
-- that more than one identity has (duplicate natural key), and an identity with more than one key (more than one
-- natural key).
--
--   Construct     the table
--   Violation     what is wrong
--   ViolationKey  the key of the rows, as an object of column and value
--   Occurrences   how many rows
--
-- The orphan checks join to the table that is referred to and look for the rows without a match. They use a
-- column of the referred table in the WHERE clause, so a RELY foreign key cannot make the optimizer drop the join.
--
-- COT_ContainerType integrity --------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_COT_ContainerType" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'COT_ContainerType',
    'duplicate primary key',
    OBJECT_CONSTRUCT('COT_ID', "COT_ID"),
    COUNT(*)
FROM
    metadata."COT_ContainerType"
GROUP BY
    "COT_ID"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'COT_ContainerType',
    'duplicate unique key',
    OBJECT_CONSTRUCT('COT_ContainerType', "COT_ContainerType"),
    COUNT(*)
FROM
    metadata."COT_ContainerType"
GROUP BY
    "COT_ContainerType"
HAVING
    COUNT(*) > 1;
-- CFT_ConfigurationType integrity --------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_CFT_ConfigurationType" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'CFT_ConfigurationType',
    'duplicate primary key',
    OBJECT_CONSTRUCT('CFT_ID', "CFT_ID"),
    COUNT(*)
FROM
    metadata."CFT_ConfigurationType"
GROUP BY
    "CFT_ID"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'CFT_ConfigurationType',
    'duplicate unique key',
    OBJECT_CONSTRUCT('CFT_ConfigurationType', "CFT_ConfigurationType"),
    COUNT(*)
FROM
    metadata."CFT_ConfigurationType"
GROUP BY
    "CFT_ConfigurationType"
HAVING
    COUNT(*) > 1;
-- TKN_TaskName integrity --------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_TKN_TaskName" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'TKN_TaskName',
    'duplicate primary key',
    OBJECT_CONSTRUCT('TKN_ID', "TKN_ID"),
    COUNT(*)
FROM
    metadata."TKN_TaskName"
GROUP BY
    "TKN_ID"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'TKN_TaskName',
    'duplicate unique key',
    OBJECT_CONSTRUCT('TKN_TaskName', "TKN_TaskName"),
    COUNT(*)
FROM
    metadata."TKN_TaskName"
GROUP BY
    "TKN_TaskName"
HAVING
    COUNT(*) > 1;
-- GRG_GraphRunGroupId integrity --------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_GRG_GraphRunGroupId" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'GRG_GraphRunGroupId',
    'duplicate primary key',
    OBJECT_CONSTRUCT('GRG_ID', "GRG_ID"),
    COUNT(*)
FROM
    metadata."GRG_GraphRunGroupId"
GROUP BY
    "GRG_ID"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'GRG_GraphRunGroupId',
    'duplicate unique key',
    OBJECT_CONSTRUCT('GRG_GraphRunGroupId', "GRG_GraphRunGroupId"),
    COUNT(*)
FROM
    metadata."GRG_GraphRunGroupId"
GROUP BY
    "GRG_GraphRunGroupId"
HAVING
    COUNT(*) > 1;
-- ILS_InstallationStatus integrity --------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_ILS_InstallationStatus" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'ILS_InstallationStatus',
    'duplicate primary key',
    OBJECT_CONSTRUCT('ILS_ID', "ILS_ID"),
    COUNT(*)
FROM
    metadata."ILS_InstallationStatus"
GROUP BY
    "ILS_ID"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'ILS_InstallationStatus',
    'duplicate unique key',
    OBJECT_CONSTRUCT('ILS_InstallationStatus', "ILS_InstallationStatus"),
    COUNT(*)
FROM
    metadata."ILS_InstallationStatus"
GROUP BY
    "ILS_InstallationStatus"
HAVING
    COUNT(*) > 1;
-- TRS_TaskRunStatus integrity --------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_TRS_TaskRunStatus" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'TRS_TaskRunStatus',
    'duplicate primary key',
    OBJECT_CONSTRUCT('TRS_ID', "TRS_ID"),
    COUNT(*)
FROM
    metadata."TRS_TaskRunStatus"
GROUP BY
    "TRS_ID"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'TRS_TaskRunStatus',
    'duplicate unique key',
    OBJECT_CONSTRUCT('TRS_TaskRunStatus', "TRS_TaskRunStatus"),
    COUNT(*)
FROM
    metadata."TRS_TaskRunStatus"
GROUP BY
    "TRS_TaskRunStatus"
HAVING
    COUNT(*) > 1;
-- TR_TaskRun integrity ------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_TR_TaskRun" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'TR_TaskRun',
    'duplicate primary key',
    OBJECT_CONSTRUCT('TR_ID', "TR_ID"),
    COUNT(*)
FROM
    metadata."TR_TaskRun"
GROUP BY
    "TR_ID"
HAVING
    COUNT(*) > 1;
-- CO_Container integrity ------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_CO_Container" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'CO_Container',
    'duplicate primary key',
    OBJECT_CONSTRUCT('CO_ID', "CO_ID"),
    COUNT(*)
FROM
    metadata."CO_Container"
GROUP BY
    "CO_ID"
HAVING
    COUNT(*) > 1;
-- CF_Configuration integrity ------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_CF_Configuration" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'CF_Configuration',
    'duplicate primary key',
    OBJECT_CONSTRUCT('CF_ID', "CF_ID"),
    COUNT(*)
FROM
    metadata."CF_Configuration"
GROUP BY
    "CF_ID"
HAVING
    COUNT(*) > 1;
-- TP_Template integrity ------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_TP_Template" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'TP_Template',
    'duplicate primary key',
    OBJECT_CONSTRUCT('TP_ID', "TP_ID"),
    COUNT(*)
FROM
    metadata."TP_Template"
GROUP BY
    "TP_ID"
HAVING
    COUNT(*) > 1;
-- OP_Operations integrity ------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_OP_Operations" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'OP_Operations',
    'duplicate primary key',
    OBJECT_CONSTRUCT('OP_ID', "OP_ID"),
    COUNT(*)
FROM
    metadata."OP_Operations"
GROUP BY
    "OP_ID"
HAVING
    COUNT(*) > 1;
-- IL_Installation integrity ------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_IL_Installation" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'IL_Installation',
    'duplicate primary key',
    OBJECT_CONSTRUCT('IL_ID', "IL_ID"),
    COUNT(*)
FROM
    metadata."IL_Installation"
GROUP BY
    "IL_ID"
HAVING
    COUNT(*) > 1;
-- TR_NAM_TaskRun_TaskName integrity ---------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_TR_NAM_TaskRun_TaskName" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'TR_NAM_TaskRun_TaskName',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'TR_NAM_TR_ID', "TR_NAM_TR_ID"
    ),
    COUNT(*)
FROM
    metadata."TR_NAM_TaskRun_TaskName"
GROUP BY
    "TR_NAM_TR_ID"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'TR_NAM_TaskRun_TaskName',
    'no row in TR_TaskRun for TR_NAM_TR_ID',
    OBJECT_CONSTRUCT('TR_NAM_TR_ID', c."TR_NAM_TR_ID"),
    COUNT(*)
FROM
    metadata."TR_NAM_TaskRun_TaskName" c
LEFT JOIN
    metadata."TR_TaskRun" p
ON
    p."TR_ID" = c."TR_NAM_TR_ID"
WHERE
    p."TR_ID" IS NULL
GROUP BY
    c."TR_NAM_TR_ID"
UNION ALL
SELECT
    'TR_NAM_TaskRun_TaskName',
    'no row in TKN_TaskName for TR_NAM_TKN_ID',
    OBJECT_CONSTRUCT('TR_NAM_TKN_ID', c."TR_NAM_TKN_ID"),
    COUNT(*)
FROM
    metadata."TR_NAM_TaskRun_TaskName" c
LEFT JOIN
    metadata."TKN_TaskName" p
ON
    p."TKN_ID" = c."TR_NAM_TKN_ID"
WHERE
    p."TKN_ID" IS NULL
GROUP BY
    c."TR_NAM_TKN_ID"
;
-- TR_GRG_TaskRun_GraphRunGroupId integrity ---------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_TR_GRG_TaskRun_GraphRunGroupId" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'TR_GRG_TaskRun_GraphRunGroupId',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'TR_GRG_TR_ID', "TR_GRG_TR_ID"
    ),
    COUNT(*)
FROM
    metadata."TR_GRG_TaskRun_GraphRunGroupId"
GROUP BY
    "TR_GRG_TR_ID"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'TR_GRG_TaskRun_GraphRunGroupId',
    'no row in TR_TaskRun for TR_GRG_TR_ID',
    OBJECT_CONSTRUCT('TR_GRG_TR_ID', c."TR_GRG_TR_ID"),
    COUNT(*)
FROM
    metadata."TR_GRG_TaskRun_GraphRunGroupId" c
LEFT JOIN
    metadata."TR_TaskRun" p
ON
    p."TR_ID" = c."TR_GRG_TR_ID"
WHERE
    p."TR_ID" IS NULL
GROUP BY
    c."TR_GRG_TR_ID"
UNION ALL
SELECT
    'TR_GRG_TaskRun_GraphRunGroupId',
    'no row in GRG_GraphRunGroupId for TR_GRG_GRG_ID',
    OBJECT_CONSTRUCT('TR_GRG_GRG_ID', c."TR_GRG_GRG_ID"),
    COUNT(*)
FROM
    metadata."TR_GRG_TaskRun_GraphRunGroupId" c
LEFT JOIN
    metadata."GRG_GraphRunGroupId" p
ON
    p."GRG_ID" = c."TR_GRG_GRG_ID"
WHERE
    p."GRG_ID" IS NULL
GROUP BY
    c."TR_GRG_GRG_ID"
;
-- TR_BEG_TaskRun_StartedAt integrity ---------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_TR_BEG_TaskRun_StartedAt" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'TR_BEG_TaskRun_StartedAt',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'TR_BEG_TR_ID', "TR_BEG_TR_ID"
    ),
    COUNT(*)
FROM
    metadata."TR_BEG_TaskRun_StartedAt"
GROUP BY
    "TR_BEG_TR_ID"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'TR_BEG_TaskRun_StartedAt',
    'no row in TR_TaskRun for TR_BEG_TR_ID',
    OBJECT_CONSTRUCT('TR_BEG_TR_ID', c."TR_BEG_TR_ID"),
    COUNT(*)
FROM
    metadata."TR_BEG_TaskRun_StartedAt" c
LEFT JOIN
    metadata."TR_TaskRun" p
ON
    p."TR_ID" = c."TR_BEG_TR_ID"
WHERE
    p."TR_ID" IS NULL
GROUP BY
    c."TR_BEG_TR_ID"
;
-- TR_FIN_TaskRun_FinishedAt integrity ---------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_TR_FIN_TaskRun_FinishedAt" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'TR_FIN_TaskRun_FinishedAt',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'TR_FIN_TR_ID', "TR_FIN_TR_ID"
    ),
    COUNT(*)
FROM
    metadata."TR_FIN_TaskRun_FinishedAt"
GROUP BY
    "TR_FIN_TR_ID"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'TR_FIN_TaskRun_FinishedAt',
    'no row in TR_TaskRun for TR_FIN_TR_ID',
    OBJECT_CONSTRUCT('TR_FIN_TR_ID', c."TR_FIN_TR_ID"),
    COUNT(*)
FROM
    metadata."TR_FIN_TaskRun_FinishedAt" c
LEFT JOIN
    metadata."TR_TaskRun" p
ON
    p."TR_ID" = c."TR_FIN_TR_ID"
WHERE
    p."TR_ID" IS NULL
GROUP BY
    c."TR_FIN_TR_ID"
;
-- TR_STA_TaskRun_Status integrity ---------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_TR_STA_TaskRun_Status" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'TR_STA_TaskRun_Status',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'TR_STA_TR_ID', "TR_STA_TR_ID"
    ),
    COUNT(*)
FROM
    metadata."TR_STA_TaskRun_Status"
GROUP BY
    "TR_STA_TR_ID"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'TR_STA_TaskRun_Status',
    'no row in TR_TaskRun for TR_STA_TR_ID',
    OBJECT_CONSTRUCT('TR_STA_TR_ID', c."TR_STA_TR_ID"),
    COUNT(*)
FROM
    metadata."TR_STA_TaskRun_Status" c
LEFT JOIN
    metadata."TR_TaskRun" p
ON
    p."TR_ID" = c."TR_STA_TR_ID"
WHERE
    p."TR_ID" IS NULL
GROUP BY
    c."TR_STA_TR_ID"
UNION ALL
SELECT
    'TR_STA_TaskRun_Status',
    'no row in TRS_TaskRunStatus for TR_STA_TRS_ID',
    OBJECT_CONSTRUCT('TR_STA_TRS_ID', c."TR_STA_TRS_ID"),
    COUNT(*)
FROM
    metadata."TR_STA_TaskRun_Status" c
LEFT JOIN
    metadata."TRS_TaskRunStatus" p
ON
    p."TRS_ID" = c."TR_STA_TRS_ID"
WHERE
    p."TRS_ID" IS NULL
GROUP BY
    c."TR_STA_TRS_ID"
;
-- TR_ERR_TaskRun_Error integrity ---------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_TR_ERR_TaskRun_Error" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'TR_ERR_TaskRun_Error',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'TR_ERR_TR_ID', "TR_ERR_TR_ID"
    ),
    COUNT(*)
FROM
    metadata."TR_ERR_TaskRun_Error"
GROUP BY
    "TR_ERR_TR_ID"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'TR_ERR_TaskRun_Error',
    'no row in TR_TaskRun for TR_ERR_TR_ID',
    OBJECT_CONSTRUCT('TR_ERR_TR_ID', c."TR_ERR_TR_ID"),
    COUNT(*)
FROM
    metadata."TR_ERR_TaskRun_Error" c
LEFT JOIN
    metadata."TR_TaskRun" p
ON
    p."TR_ID" = c."TR_ERR_TR_ID"
WHERE
    p."TR_ID" IS NULL
GROUP BY
    c."TR_ERR_TR_ID"
;
-- CO_NAM_Container_Name integrity ---------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_CO_NAM_Container_Name" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'CO_NAM_Container_Name',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'CO_NAM_CO_ID', "CO_NAM_CO_ID"
    ),
    COUNT(*)
FROM
    metadata."CO_NAM_Container_Name"
GROUP BY
    "CO_NAM_CO_ID"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'CO_NAM_Container_Name',
    'no row in CO_Container for CO_NAM_CO_ID',
    OBJECT_CONSTRUCT('CO_NAM_CO_ID', c."CO_NAM_CO_ID"),
    COUNT(*)
FROM
    metadata."CO_NAM_Container_Name" c
LEFT JOIN
    metadata."CO_Container" p
ON
    p."CO_ID" = c."CO_NAM_CO_ID"
WHERE
    p."CO_ID" IS NULL
GROUP BY
    c."CO_NAM_CO_ID"
;
-- CO_TYP_Container_Type integrity ---------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_CO_TYP_Container_Type" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'CO_TYP_Container_Type',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'CO_TYP_CO_ID', "CO_TYP_CO_ID"
    ),
    COUNT(*)
FROM
    metadata."CO_TYP_Container_Type"
GROUP BY
    "CO_TYP_CO_ID"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'CO_TYP_Container_Type',
    'no row in CO_Container for CO_TYP_CO_ID',
    OBJECT_CONSTRUCT('CO_TYP_CO_ID', c."CO_TYP_CO_ID"),
    COUNT(*)
FROM
    metadata."CO_TYP_Container_Type" c
LEFT JOIN
    metadata."CO_Container" p
ON
    p."CO_ID" = c."CO_TYP_CO_ID"
WHERE
    p."CO_ID" IS NULL
GROUP BY
    c."CO_TYP_CO_ID"
UNION ALL
SELECT
    'CO_TYP_Container_Type',
    'no row in COT_ContainerType for CO_TYP_COT_ID',
    OBJECT_CONSTRUCT('CO_TYP_COT_ID', c."CO_TYP_COT_ID"),
    COUNT(*)
FROM
    metadata."CO_TYP_Container_Type" c
LEFT JOIN
    metadata."COT_ContainerType" p
ON
    p."COT_ID" = c."CO_TYP_COT_ID"
WHERE
    p."COT_ID" IS NULL
GROUP BY
    c."CO_TYP_COT_ID"
;
-- CO_DSC_Container_Discovered integrity ---------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_CO_DSC_Container_Discovered" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'CO_DSC_Container_Discovered',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'CO_DSC_CO_ID', "CO_DSC_CO_ID",
        'CO_DSC_ChangedAt', "CO_DSC_ChangedAt"
    ),
    COUNT(*)
FROM
    metadata."CO_DSC_Container_Discovered"
GROUP BY
    "CO_DSC_CO_ID",
    "CO_DSC_ChangedAt"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'CO_DSC_Container_Discovered',
    'no row in CO_Container for CO_DSC_CO_ID',
    OBJECT_CONSTRUCT('CO_DSC_CO_ID', c."CO_DSC_CO_ID"),
    COUNT(*)
FROM
    metadata."CO_DSC_Container_Discovered" c
LEFT JOIN
    metadata."CO_Container" p
ON
    p."CO_ID" = c."CO_DSC_CO_ID"
WHERE
    p."CO_ID" IS NULL
GROUP BY
    c."CO_DSC_CO_ID"
UNION ALL
SELECT
    'CO_DSC_Container_Discovered',
    'restatement',
    OBJECT_CONSTRUCT(
        'CO_DSC_CO_ID', "CO_DSC_CO_ID",
        'CO_DSC_ChangedAt', "CO_DSC_ChangedAt"
    ),
    1
FROM (
    SELECT
        "CO_DSC_CO_ID",
        "CO_DSC_ChangedAt",
        "CO_DSC_Container_Discovered" AS compared,
        LAG("CO_DSC_Container_Discovered") OVER (
            PARTITION BY
                "CO_DSC_CO_ID"
            ORDER BY
                "CO_DSC_ChangedAt"
        ) AS previous
    FROM
        metadata."CO_DSC_Container_Discovered"
)
WHERE
    compared = previous
;
-- CF_NAM_Configuration_Name integrity ---------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_CF_NAM_Configuration_Name" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'CF_NAM_Configuration_Name',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'CF_NAM_CF_ID', "CF_NAM_CF_ID"
    ),
    COUNT(*)
FROM
    metadata."CF_NAM_Configuration_Name"
GROUP BY
    "CF_NAM_CF_ID"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'CF_NAM_Configuration_Name',
    'no row in CF_Configuration for CF_NAM_CF_ID',
    OBJECT_CONSTRUCT('CF_NAM_CF_ID', c."CF_NAM_CF_ID"),
    COUNT(*)
FROM
    metadata."CF_NAM_Configuration_Name" c
LEFT JOIN
    metadata."CF_Configuration" p
ON
    p."CF_ID" = c."CF_NAM_CF_ID"
WHERE
    p."CF_ID" IS NULL
GROUP BY
    c."CF_NAM_CF_ID"
;
-- CF_CNT_Configuration_Content integrity ---------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_CF_CNT_Configuration_Content" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'CF_CNT_Configuration_Content',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'CF_CNT_CF_ID', "CF_CNT_CF_ID",
        'CF_CNT_ChangedAt', "CF_CNT_ChangedAt"
    ),
    COUNT(*)
FROM
    metadata."CF_CNT_Configuration_Content"
GROUP BY
    "CF_CNT_CF_ID",
    "CF_CNT_ChangedAt"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'CF_CNT_Configuration_Content',
    'no row in CF_Configuration for CF_CNT_CF_ID',
    OBJECT_CONSTRUCT('CF_CNT_CF_ID', c."CF_CNT_CF_ID"),
    COUNT(*)
FROM
    metadata."CF_CNT_Configuration_Content" c
LEFT JOIN
    metadata."CF_Configuration" p
ON
    p."CF_ID" = c."CF_CNT_CF_ID"
WHERE
    p."CF_ID" IS NULL
GROUP BY
    c."CF_CNT_CF_ID"
UNION ALL
SELECT
    'CF_CNT_Configuration_Content',
    'restatement',
    OBJECT_CONSTRUCT(
        'CF_CNT_CF_ID', "CF_CNT_CF_ID",
        'CF_CNT_ChangedAt', "CF_CNT_ChangedAt"
    ),
    1
FROM (
    SELECT
        "CF_CNT_CF_ID",
        "CF_CNT_ChangedAt",
        "CF_CNT_Checksum" AS compared,
        LAG("CF_CNT_Checksum") OVER (
            PARTITION BY
                "CF_CNT_CF_ID"
            ORDER BY
                "CF_CNT_ChangedAt"
        ) AS previous
    FROM
        metadata."CF_CNT_Configuration_Content"
)
WHERE
    compared = previous
;
-- CF_TYP_Configuration_Type integrity ---------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_CF_TYP_Configuration_Type" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'CF_TYP_Configuration_Type',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'CF_TYP_CF_ID', "CF_TYP_CF_ID"
    ),
    COUNT(*)
FROM
    metadata."CF_TYP_Configuration_Type"
GROUP BY
    "CF_TYP_CF_ID"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'CF_TYP_Configuration_Type',
    'no row in CF_Configuration for CF_TYP_CF_ID',
    OBJECT_CONSTRUCT('CF_TYP_CF_ID', c."CF_TYP_CF_ID"),
    COUNT(*)
FROM
    metadata."CF_TYP_Configuration_Type" c
LEFT JOIN
    metadata."CF_Configuration" p
ON
    p."CF_ID" = c."CF_TYP_CF_ID"
WHERE
    p."CF_ID" IS NULL
GROUP BY
    c."CF_TYP_CF_ID"
UNION ALL
SELECT
    'CF_TYP_Configuration_Type',
    'no row in CFT_ConfigurationType for CF_TYP_CFT_ID',
    OBJECT_CONSTRUCT('CF_TYP_CFT_ID', c."CF_TYP_CFT_ID"),
    COUNT(*)
FROM
    metadata."CF_TYP_Configuration_Type" c
LEFT JOIN
    metadata."CFT_ConfigurationType" p
ON
    p."CFT_ID" = c."CF_TYP_CFT_ID"
WHERE
    p."CFT_ID" IS NULL
GROUP BY
    c."CF_TYP_CFT_ID"
;
-- TP_NAM_Template_Name integrity ---------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_TP_NAM_Template_Name" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'TP_NAM_Template_Name',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'TP_NAM_TP_ID', "TP_NAM_TP_ID"
    ),
    COUNT(*)
FROM
    metadata."TP_NAM_Template_Name"
GROUP BY
    "TP_NAM_TP_ID"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'TP_NAM_Template_Name',
    'no row in TP_Template for TP_NAM_TP_ID',
    OBJECT_CONSTRUCT('TP_NAM_TP_ID', c."TP_NAM_TP_ID"),
    COUNT(*)
FROM
    metadata."TP_NAM_Template_Name" c
LEFT JOIN
    metadata."TP_Template" p
ON
    p."TP_ID" = c."TP_NAM_TP_ID"
WHERE
    p."TP_ID" IS NULL
GROUP BY
    c."TP_NAM_TP_ID"
;
-- TP_CNT_Template_Content integrity ---------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_TP_CNT_Template_Content" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'TP_CNT_Template_Content',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'TP_CNT_TP_ID', "TP_CNT_TP_ID",
        'TP_CNT_ChangedAt', "TP_CNT_ChangedAt"
    ),
    COUNT(*)
FROM
    metadata."TP_CNT_Template_Content"
GROUP BY
    "TP_CNT_TP_ID",
    "TP_CNT_ChangedAt"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'TP_CNT_Template_Content',
    'no row in TP_Template for TP_CNT_TP_ID',
    OBJECT_CONSTRUCT('TP_CNT_TP_ID', c."TP_CNT_TP_ID"),
    COUNT(*)
FROM
    metadata."TP_CNT_Template_Content" c
LEFT JOIN
    metadata."TP_Template" p
ON
    p."TP_ID" = c."TP_CNT_TP_ID"
WHERE
    p."TP_ID" IS NULL
GROUP BY
    c."TP_CNT_TP_ID"
UNION ALL
SELECT
    'TP_CNT_Template_Content',
    'restatement',
    OBJECT_CONSTRUCT(
        'TP_CNT_TP_ID', "TP_CNT_TP_ID",
        'TP_CNT_ChangedAt', "TP_CNT_ChangedAt"
    ),
    1
FROM (
    SELECT
        "TP_CNT_TP_ID",
        "TP_CNT_ChangedAt",
        "TP_CNT_Checksum" AS compared,
        LAG("TP_CNT_Checksum") OVER (
            PARTITION BY
                "TP_CNT_TP_ID"
            ORDER BY
                "TP_CNT_ChangedAt"
        ) AS previous
    FROM
        metadata."TP_CNT_Template_Content"
)
WHERE
    compared = previous
;
-- OP_INS_Operations_RowsInserted integrity ---------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_OP_INS_Operations_RowsInserted" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'OP_INS_Operations_RowsInserted',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'OP_INS_OP_ID', "OP_INS_OP_ID",
        'OP_INS_ChangedAt', "OP_INS_ChangedAt"
    ),
    COUNT(*)
FROM
    metadata."OP_INS_Operations_RowsInserted"
GROUP BY
    "OP_INS_OP_ID",
    "OP_INS_ChangedAt"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'OP_INS_Operations_RowsInserted',
    'no row in OP_Operations for OP_INS_OP_ID',
    OBJECT_CONSTRUCT('OP_INS_OP_ID', c."OP_INS_OP_ID"),
    COUNT(*)
FROM
    metadata."OP_INS_Operations_RowsInserted" c
LEFT JOIN
    metadata."OP_Operations" p
ON
    p."OP_ID" = c."OP_INS_OP_ID"
WHERE
    p."OP_ID" IS NULL
GROUP BY
    c."OP_INS_OP_ID"
UNION ALL
SELECT
    'OP_INS_Operations_RowsInserted',
    'restatement',
    OBJECT_CONSTRUCT(
        'OP_INS_OP_ID', "OP_INS_OP_ID",
        'OP_INS_ChangedAt', "OP_INS_ChangedAt"
    ),
    1
FROM (
    SELECT
        "OP_INS_OP_ID",
        "OP_INS_ChangedAt",
        "OP_INS_Operations_RowsInserted" AS compared,
        LAG("OP_INS_Operations_RowsInserted") OVER (
            PARTITION BY
                "OP_INS_OP_ID"
            ORDER BY
                "OP_INS_ChangedAt"
        ) AS previous
    FROM
        metadata."OP_INS_Operations_RowsInserted"
)
WHERE
    compared = previous
;
-- OP_UPD_Operations_RowsUpdated integrity ---------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_OP_UPD_Operations_RowsUpdated" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'OP_UPD_Operations_RowsUpdated',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'OP_UPD_OP_ID', "OP_UPD_OP_ID",
        'OP_UPD_ChangedAt', "OP_UPD_ChangedAt"
    ),
    COUNT(*)
FROM
    metadata."OP_UPD_Operations_RowsUpdated"
GROUP BY
    "OP_UPD_OP_ID",
    "OP_UPD_ChangedAt"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'OP_UPD_Operations_RowsUpdated',
    'no row in OP_Operations for OP_UPD_OP_ID',
    OBJECT_CONSTRUCT('OP_UPD_OP_ID', c."OP_UPD_OP_ID"),
    COUNT(*)
FROM
    metadata."OP_UPD_Operations_RowsUpdated" c
LEFT JOIN
    metadata."OP_Operations" p
ON
    p."OP_ID" = c."OP_UPD_OP_ID"
WHERE
    p."OP_ID" IS NULL
GROUP BY
    c."OP_UPD_OP_ID"
UNION ALL
SELECT
    'OP_UPD_Operations_RowsUpdated',
    'restatement',
    OBJECT_CONSTRUCT(
        'OP_UPD_OP_ID', "OP_UPD_OP_ID",
        'OP_UPD_ChangedAt', "OP_UPD_ChangedAt"
    ),
    1
FROM (
    SELECT
        "OP_UPD_OP_ID",
        "OP_UPD_ChangedAt",
        "OP_UPD_Operations_RowsUpdated" AS compared,
        LAG("OP_UPD_Operations_RowsUpdated") OVER (
            PARTITION BY
                "OP_UPD_OP_ID"
            ORDER BY
                "OP_UPD_ChangedAt"
        ) AS previous
    FROM
        metadata."OP_UPD_Operations_RowsUpdated"
)
WHERE
    compared = previous
;
-- OP_DEL_Operations_RowsDeleted integrity ---------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_OP_DEL_Operations_RowsDeleted" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'OP_DEL_Operations_RowsDeleted',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'OP_DEL_OP_ID', "OP_DEL_OP_ID",
        'OP_DEL_ChangedAt', "OP_DEL_ChangedAt"
    ),
    COUNT(*)
FROM
    metadata."OP_DEL_Operations_RowsDeleted"
GROUP BY
    "OP_DEL_OP_ID",
    "OP_DEL_ChangedAt"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'OP_DEL_Operations_RowsDeleted',
    'no row in OP_Operations for OP_DEL_OP_ID',
    OBJECT_CONSTRUCT('OP_DEL_OP_ID', c."OP_DEL_OP_ID"),
    COUNT(*)
FROM
    metadata."OP_DEL_Operations_RowsDeleted" c
LEFT JOIN
    metadata."OP_Operations" p
ON
    p."OP_ID" = c."OP_DEL_OP_ID"
WHERE
    p."OP_ID" IS NULL
GROUP BY
    c."OP_DEL_OP_ID"
UNION ALL
SELECT
    'OP_DEL_Operations_RowsDeleted',
    'restatement',
    OBJECT_CONSTRUCT(
        'OP_DEL_OP_ID', "OP_DEL_OP_ID",
        'OP_DEL_ChangedAt', "OP_DEL_ChangedAt"
    ),
    1
FROM (
    SELECT
        "OP_DEL_OP_ID",
        "OP_DEL_ChangedAt",
        "OP_DEL_Operations_RowsDeleted" AS compared,
        LAG("OP_DEL_Operations_RowsDeleted") OVER (
            PARTITION BY
                "OP_DEL_OP_ID"
            ORDER BY
                "OP_DEL_ChangedAt"
        ) AS previous
    FROM
        metadata."OP_DEL_Operations_RowsDeleted"
)
WHERE
    compared = previous
;
-- OP_MRG_Operations_RowsMerged integrity ---------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_OP_MRG_Operations_RowsMerged" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'OP_MRG_Operations_RowsMerged',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'OP_MRG_OP_ID', "OP_MRG_OP_ID",
        'OP_MRG_ChangedAt', "OP_MRG_ChangedAt"
    ),
    COUNT(*)
FROM
    metadata."OP_MRG_Operations_RowsMerged"
GROUP BY
    "OP_MRG_OP_ID",
    "OP_MRG_ChangedAt"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'OP_MRG_Operations_RowsMerged',
    'no row in OP_Operations for OP_MRG_OP_ID',
    OBJECT_CONSTRUCT('OP_MRG_OP_ID', c."OP_MRG_OP_ID"),
    COUNT(*)
FROM
    metadata."OP_MRG_Operations_RowsMerged" c
LEFT JOIN
    metadata."OP_Operations" p
ON
    p."OP_ID" = c."OP_MRG_OP_ID"
WHERE
    p."OP_ID" IS NULL
GROUP BY
    c."OP_MRG_OP_ID"
UNION ALL
SELECT
    'OP_MRG_Operations_RowsMerged',
    'restatement',
    OBJECT_CONSTRUCT(
        'OP_MRG_OP_ID', "OP_MRG_OP_ID",
        'OP_MRG_ChangedAt', "OP_MRG_ChangedAt"
    ),
    1
FROM (
    SELECT
        "OP_MRG_OP_ID",
        "OP_MRG_ChangedAt",
        "OP_MRG_Operations_RowsMerged" AS compared,
        LAG("OP_MRG_Operations_RowsMerged") OVER (
            PARTITION BY
                "OP_MRG_OP_ID"
            ORDER BY
                "OP_MRG_ChangedAt"
        ) AS previous
    FROM
        metadata."OP_MRG_Operations_RowsMerged"
)
WHERE
    compared = previous
;
-- IL_RID_Installation_RunId integrity ---------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_IL_RID_Installation_RunId" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'IL_RID_Installation_RunId',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'IL_RID_IL_ID', "IL_RID_IL_ID"
    ),
    COUNT(*)
FROM
    metadata."IL_RID_Installation_RunId"
GROUP BY
    "IL_RID_IL_ID"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'IL_RID_Installation_RunId',
    'no row in IL_Installation for IL_RID_IL_ID',
    OBJECT_CONSTRUCT('IL_RID_IL_ID', c."IL_RID_IL_ID"),
    COUNT(*)
FROM
    metadata."IL_RID_Installation_RunId" c
LEFT JOIN
    metadata."IL_Installation" p
ON
    p."IL_ID" = c."IL_RID_IL_ID"
WHERE
    p."IL_ID" IS NULL
GROUP BY
    c."IL_RID_IL_ID"
;
-- IL_DDL_Installation_RenderedSql integrity ---------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_IL_DDL_Installation_RenderedSql" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'IL_DDL_Installation_RenderedSql',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'IL_DDL_IL_ID', "IL_DDL_IL_ID"
    ),
    COUNT(*)
FROM
    metadata."IL_DDL_Installation_RenderedSql"
GROUP BY
    "IL_DDL_IL_ID"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'IL_DDL_Installation_RenderedSql',
    'no row in IL_Installation for IL_DDL_IL_ID',
    OBJECT_CONSTRUCT('IL_DDL_IL_ID', c."IL_DDL_IL_ID"),
    COUNT(*)
FROM
    metadata."IL_DDL_Installation_RenderedSql" c
LEFT JOIN
    metadata."IL_Installation" p
ON
    p."IL_ID" = c."IL_DDL_IL_ID"
WHERE
    p."IL_ID" IS NULL
GROUP BY
    c."IL_DDL_IL_ID"
;
-- IL_RAT_Installation_RenderedAt integrity ---------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_IL_RAT_Installation_RenderedAt" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'IL_RAT_Installation_RenderedAt',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'IL_RAT_IL_ID', "IL_RAT_IL_ID"
    ),
    COUNT(*)
FROM
    metadata."IL_RAT_Installation_RenderedAt"
GROUP BY
    "IL_RAT_IL_ID"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'IL_RAT_Installation_RenderedAt',
    'no row in IL_Installation for IL_RAT_IL_ID',
    OBJECT_CONSTRUCT('IL_RAT_IL_ID', c."IL_RAT_IL_ID"),
    COUNT(*)
FROM
    metadata."IL_RAT_Installation_RenderedAt" c
LEFT JOIN
    metadata."IL_Installation" p
ON
    p."IL_ID" = c."IL_RAT_IL_ID"
WHERE
    p."IL_ID" IS NULL
GROUP BY
    c."IL_RAT_IL_ID"
;
-- IL_STA_Installation_Status integrity ---------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_IL_STA_Installation_Status" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'IL_STA_Installation_Status',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'IL_STA_IL_ID', "IL_STA_IL_ID"
    ),
    COUNT(*)
FROM
    metadata."IL_STA_Installation_Status"
GROUP BY
    "IL_STA_IL_ID"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'IL_STA_Installation_Status',
    'no row in IL_Installation for IL_STA_IL_ID',
    OBJECT_CONSTRUCT('IL_STA_IL_ID', c."IL_STA_IL_ID"),
    COUNT(*)
FROM
    metadata."IL_STA_Installation_Status" c
LEFT JOIN
    metadata."IL_Installation" p
ON
    p."IL_ID" = c."IL_STA_IL_ID"
WHERE
    p."IL_ID" IS NULL
GROUP BY
    c."IL_STA_IL_ID"
UNION ALL
SELECT
    'IL_STA_Installation_Status',
    'no row in ILS_InstallationStatus for IL_STA_ILS_ID',
    OBJECT_CONSTRUCT('IL_STA_ILS_ID', c."IL_STA_ILS_ID"),
    COUNT(*)
FROM
    metadata."IL_STA_Installation_Status" c
LEFT JOIN
    metadata."ILS_InstallationStatus" p
ON
    p."ILS_ID" = c."IL_STA_ILS_ID"
WHERE
    p."ILS_ID" IS NULL
GROUP BY
    c."IL_STA_ILS_ID"
;
-- IL_ERR_Installation_Error integrity ---------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_IL_ERR_Installation_Error" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'IL_ERR_Installation_Error',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'IL_ERR_IL_ID', "IL_ERR_IL_ID"
    ),
    COUNT(*)
FROM
    metadata."IL_ERR_Installation_Error"
GROUP BY
    "IL_ERR_IL_ID"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'IL_ERR_Installation_Error',
    'no row in IL_Installation for IL_ERR_IL_ID',
    OBJECT_CONSTRUCT('IL_ERR_IL_ID', c."IL_ERR_IL_ID"),
    COUNT(*)
FROM
    metadata."IL_ERR_Installation_Error" c
LEFT JOIN
    metadata."IL_Installation" p
ON
    p."IL_ID" = c."IL_ERR_IL_ID"
WHERE
    p."IL_ID" IS NULL
GROUP BY
    c."IL_ERR_IL_ID"
;
-- TR_operates_CO_source_CO_target_OP_with integrity ---------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_TR_operates_CO_source_CO_target_OP_with" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'TR_operates_CO_source_CO_target_OP_with',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'TR_ID_operates', "TR_ID_operates",
        'CO_ID_source', "CO_ID_source",
        'CO_ID_target', "CO_ID_target"
    ),
    COUNT(*)
FROM
    metadata."TR_operates_CO_source_CO_target_OP_with"
GROUP BY
    "TR_ID_operates",
    "CO_ID_source",
    "CO_ID_target"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'TR_operates_CO_source_CO_target_OP_with',
    'no row in TR_TaskRun for TR_ID_operates',
    OBJECT_CONSTRUCT('TR_ID_operates', c."TR_ID_operates"),
    COUNT(*)
FROM
    metadata."TR_operates_CO_source_CO_target_OP_with" c
LEFT JOIN
    metadata."TR_TaskRun" p
ON
    p."TR_ID" = c."TR_ID_operates"
WHERE
    p."TR_ID" IS NULL
GROUP BY
    c."TR_ID_operates"
UNION ALL
SELECT
    'TR_operates_CO_source_CO_target_OP_with',
    'no row in CO_Container for CO_ID_source',
    OBJECT_CONSTRUCT('CO_ID_source', c."CO_ID_source"),
    COUNT(*)
FROM
    metadata."TR_operates_CO_source_CO_target_OP_with" c
LEFT JOIN
    metadata."CO_Container" p
ON
    p."CO_ID" = c."CO_ID_source"
WHERE
    p."CO_ID" IS NULL
GROUP BY
    c."CO_ID_source"
UNION ALL
SELECT
    'TR_operates_CO_source_CO_target_OP_with',
    'no row in CO_Container for CO_ID_target',
    OBJECT_CONSTRUCT('CO_ID_target', c."CO_ID_target"),
    COUNT(*)
FROM
    metadata."TR_operates_CO_source_CO_target_OP_with" c
LEFT JOIN
    metadata."CO_Container" p
ON
    p."CO_ID" = c."CO_ID_target"
WHERE
    p."CO_ID" IS NULL
GROUP BY
    c."CO_ID_target"
UNION ALL
SELECT
    'TR_operates_CO_source_CO_target_OP_with',
    'no row in OP_Operations for OP_ID_with',
    OBJECT_CONSTRUCT('OP_ID_with', c."OP_ID_with"),
    COUNT(*)
FROM
    metadata."TR_operates_CO_source_CO_target_OP_with" c
LEFT JOIN
    metadata."OP_Operations" p
ON
    p."OP_ID" = c."OP_ID_with"
WHERE
    p."OP_ID" IS NULL
GROUP BY
    c."OP_ID_with"
;
-- TR_formed_CF_from integrity ---------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_TR_formed_CF_from" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'TR_formed_CF_from',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'TR_ID_formed', "TR_ID_formed"
    ),
    COUNT(*)
FROM
    metadata."TR_formed_CF_from"
GROUP BY
    "TR_ID_formed"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'TR_formed_CF_from',
    'no row in TR_TaskRun for TR_ID_formed',
    OBJECT_CONSTRUCT('TR_ID_formed', c."TR_ID_formed"),
    COUNT(*)
FROM
    metadata."TR_formed_CF_from" c
LEFT JOIN
    metadata."TR_TaskRun" p
ON
    p."TR_ID" = c."TR_ID_formed"
WHERE
    p."TR_ID" IS NULL
GROUP BY
    c."TR_ID_formed"
UNION ALL
SELECT
    'TR_formed_CF_from',
    'no row in CF_Configuration for CF_ID_from',
    OBJECT_CONSTRUCT('CF_ID_from', c."CF_ID_from"),
    COUNT(*)
FROM
    metadata."TR_formed_CF_from" c
LEFT JOIN
    metadata."CF_Configuration" p
ON
    p."CF_ID" = c."CF_ID_from"
WHERE
    p."CF_ID" IS NULL
GROUP BY
    c."CF_ID_from"
;
-- CF_uses_TP_template integrity ---------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_CF_uses_TP_template" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'CF_uses_TP_template',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'CF_ID_uses', "CF_ID_uses"
    ),
    COUNT(*)
FROM
    metadata."CF_uses_TP_template"
GROUP BY
    "CF_ID_uses"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'CF_uses_TP_template',
    'no row in CF_Configuration for CF_ID_uses',
    OBJECT_CONSTRUCT('CF_ID_uses', c."CF_ID_uses"),
    COUNT(*)
FROM
    metadata."CF_uses_TP_template" c
LEFT JOIN
    metadata."CF_Configuration" p
ON
    p."CF_ID" = c."CF_ID_uses"
WHERE
    p."CF_ID" IS NULL
GROUP BY
    c."CF_ID_uses"
UNION ALL
SELECT
    'CF_uses_TP_template',
    'no row in TP_Template for TP_ID_template',
    OBJECT_CONSTRUCT('TP_ID_template', c."TP_ID_template"),
    COUNT(*)
FROM
    metadata."CF_uses_TP_template" c
LEFT JOIN
    metadata."TP_Template" p
ON
    p."TP_ID" = c."TP_ID_template"
WHERE
    p."TP_ID" IS NULL
GROUP BY
    c."TP_ID_template"
;
-- IL_installs_CF_configuration integrity ---------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_IL_installs_CF_configuration" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'IL_installs_CF_configuration',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'IL_ID_installs', "IL_ID_installs"
    ),
    COUNT(*)
FROM
    metadata."IL_installs_CF_configuration"
GROUP BY
    "IL_ID_installs"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'IL_installs_CF_configuration',
    'no row in IL_Installation for IL_ID_installs',
    OBJECT_CONSTRUCT('IL_ID_installs', c."IL_ID_installs"),
    COUNT(*)
FROM
    metadata."IL_installs_CF_configuration" c
LEFT JOIN
    metadata."IL_Installation" p
ON
    p."IL_ID" = c."IL_ID_installs"
WHERE
    p."IL_ID" IS NULL
GROUP BY
    c."IL_ID_installs"
UNION ALL
SELECT
    'IL_installs_CF_configuration',
    'no row in CF_Configuration for CF_ID_configuration',
    OBJECT_CONSTRUCT('CF_ID_configuration', c."CF_ID_configuration"),
    COUNT(*)
FROM
    metadata."IL_installs_CF_configuration" c
LEFT JOIN
    metadata."CF_Configuration" p
ON
    p."CF_ID" = c."CF_ID_configuration"
WHERE
    p."CF_ID" IS NULL
GROUP BY
    c."CF_ID_configuration"
;
-- IL_applies_TP_rendered integrity ---------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata."ic_IL_applies_TP_rendered" (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    'IL_applies_TP_rendered',
    'duplicate primary key',
    OBJECT_CONSTRUCT(
        'IL_ID_applies', "IL_ID_applies"
    ),
    COUNT(*)
FROM
    metadata."IL_applies_TP_rendered"
GROUP BY
    "IL_ID_applies"
HAVING
    COUNT(*) > 1
UNION ALL
SELECT
    'IL_applies_TP_rendered',
    'no row in IL_Installation for IL_ID_applies',
    OBJECT_CONSTRUCT('IL_ID_applies', c."IL_ID_applies"),
    COUNT(*)
FROM
    metadata."IL_applies_TP_rendered" c
LEFT JOIN
    metadata."IL_Installation" p
ON
    p."IL_ID" = c."IL_ID_applies"
WHERE
    p."IL_ID" IS NULL
GROUP BY
    c."IL_ID_applies"
UNION ALL
SELECT
    'IL_applies_TP_rendered',
    'no row in TP_Template for TP_ID_rendered',
    OBJECT_CONSTRUCT('TP_ID_rendered', c."TP_ID_rendered"),
    COUNT(*)
FROM
    metadata."IL_applies_TP_rendered" c
LEFT JOIN
    metadata."TP_Template" p
ON
    p."TP_ID" = c."TP_ID_rendered"
WHERE
    p."TP_ID" IS NULL
GROUP BY
    c."TP_ID_rendered"
;
-- IntegrityViolations ------------------------------------------------------------------------------------------------
-- Every integrity check of the model, in one view.
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata.IntegrityViolations (
    Construct,
    Violation,
    ViolationKey,
    Occurrences
)
COPY GRANTS
AS
SELECT
    CAST(NULL AS VARCHAR),
    CAST(NULL AS VARCHAR),
    CAST(NULL AS OBJECT),
    CAST(NULL AS NUMBER)
WHERE
    FALSE
UNION ALL SELECT * FROM metadata."ic_COT_ContainerType"
UNION ALL SELECT * FROM metadata."ic_CFT_ConfigurationType"
UNION ALL SELECT * FROM metadata."ic_TKN_TaskName"
UNION ALL SELECT * FROM metadata."ic_GRG_GraphRunGroupId"
UNION ALL SELECT * FROM metadata."ic_ILS_InstallationStatus"
UNION ALL SELECT * FROM metadata."ic_TRS_TaskRunStatus"
UNION ALL SELECT * FROM metadata."ic_TR_TaskRun"
UNION ALL SELECT * FROM metadata."ic_CO_Container"
UNION ALL SELECT * FROM metadata."ic_CF_Configuration"
UNION ALL SELECT * FROM metadata."ic_TP_Template"
UNION ALL SELECT * FROM metadata."ic_OP_Operations"
UNION ALL SELECT * FROM metadata."ic_IL_Installation"
UNION ALL SELECT * FROM metadata."ic_TR_NAM_TaskRun_TaskName"
UNION ALL SELECT * FROM metadata."ic_TR_GRG_TaskRun_GraphRunGroupId"
UNION ALL SELECT * FROM metadata."ic_TR_BEG_TaskRun_StartedAt"
UNION ALL SELECT * FROM metadata."ic_TR_FIN_TaskRun_FinishedAt"
UNION ALL SELECT * FROM metadata."ic_TR_STA_TaskRun_Status"
UNION ALL SELECT * FROM metadata."ic_TR_ERR_TaskRun_Error"
UNION ALL SELECT * FROM metadata."ic_CO_NAM_Container_Name"
UNION ALL SELECT * FROM metadata."ic_CO_TYP_Container_Type"
UNION ALL SELECT * FROM metadata."ic_CO_DSC_Container_Discovered"
UNION ALL SELECT * FROM metadata."ic_CF_NAM_Configuration_Name"
UNION ALL SELECT * FROM metadata."ic_CF_CNT_Configuration_Content"
UNION ALL SELECT * FROM metadata."ic_CF_TYP_Configuration_Type"
UNION ALL SELECT * FROM metadata."ic_TP_NAM_Template_Name"
UNION ALL SELECT * FROM metadata."ic_TP_CNT_Template_Content"
UNION ALL SELECT * FROM metadata."ic_OP_INS_Operations_RowsInserted"
UNION ALL SELECT * FROM metadata."ic_OP_UPD_Operations_RowsUpdated"
UNION ALL SELECT * FROM metadata."ic_OP_DEL_Operations_RowsDeleted"
UNION ALL SELECT * FROM metadata."ic_OP_MRG_Operations_RowsMerged"
UNION ALL SELECT * FROM metadata."ic_IL_RID_Installation_RunId"
UNION ALL SELECT * FROM metadata."ic_IL_DDL_Installation_RenderedSql"
UNION ALL SELECT * FROM metadata."ic_IL_RAT_Installation_RenderedAt"
UNION ALL SELECT * FROM metadata."ic_IL_STA_Installation_Status"
UNION ALL SELECT * FROM metadata."ic_IL_ERR_Installation_Error"
UNION ALL SELECT * FROM metadata."ic_TR_operates_CO_source_CO_target_OP_with"
UNION ALL SELECT * FROM metadata."ic_TR_formed_CF_from"
UNION ALL SELECT * FROM metadata."ic_CF_uses_TP_template"
UNION ALL SELECT * FROM metadata."ic_IL_installs_CF_configuration"
UNION ALL SELECT * FROM metadata."ic_IL_applies_TP_rendered"
;
-- DESCRIPTIONS -------------------------------------------------------------------------------------------------------
--
-- Descriptions in the model are added as comments on the schema, tables, and the columns holding values and
-- references, making them available to catalogs and semantic layers. Views get their comments when they are
-- created, since Snowflake does not allow comments on view columns to be added afterwards.
--
