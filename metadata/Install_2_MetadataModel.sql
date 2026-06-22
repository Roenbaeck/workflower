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
CREATE TABLE IF NOT EXISTS metadata.COT_ContainerType (
    COT_ID tinyint not null,
    COT_ContainerType varchar(42) not null,
    constraint pkCOT_ContainerType primary key (
        COT_ID
    ),
    constraint uqCOT_ContainerType unique (
        COT_ContainerType
    )
) CLUSTER BY (COT_ID);
-- Knot table ---------------------------------------------------------------------------------------------------------
-- CFT_ConfigurationType table
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata.CFT_ConfigurationType (
    CFT_ID tinyint not null,
    CFT_ConfigurationType varchar(42) not null,
    constraint pkCFT_ConfigurationType primary key (
        CFT_ID
    ),
    constraint uqCFT_ConfigurationType unique (
        CFT_ConfigurationType
    )
) CLUSTER BY (CFT_ID);
-- Knot table ---------------------------------------------------------------------------------------------------------
-- TKN_TaskName table
-----------------------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS metadata.TKN_TaskName_ID_SEQ START 1 INCREMENT 1;
CREATE TABLE IF NOT EXISTS metadata.TKN_TaskName (
    TKN_ID int default metadata.TKN_TaskName_ID_SEQ.nextval not null, 
    TKN_TaskName varchar(500) not null,
    constraint pkTKN_TaskName primary key (
        TKN_ID
    ),
    constraint uqTKN_TaskName unique (
        TKN_TaskName
    )
) CLUSTER BY (TKN_ID);
-- Knot table ---------------------------------------------------------------------------------------------------------
-- GRG_GraphRunGroupId table
-----------------------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS metadata.GRG_GraphRunGroupId_ID_SEQ START 1 INCREMENT 1;
CREATE TABLE IF NOT EXISTS metadata.GRG_GraphRunGroupId (
    GRG_ID int default metadata.GRG_GraphRunGroupId_ID_SEQ.nextval not null, 
    GRG_GraphRunGroupId varchar(100) not null,
    constraint pkGRG_GraphRunGroupId primary key (
        GRG_ID
    ),
    constraint uqGRG_GraphRunGroupId unique (
        GRG_GraphRunGroupId
    )
) CLUSTER BY (GRG_ID);
-- ANCHORS ------------------------------------------------------------------------------------------------------------
--
-- Anchors are used to store the identities of entities.
-- Anchors are immutable.
--
-- Anchor table -------------------------------------------------------------------------------------------------------
-- TR_TaskRun table (with 2 attributes)
-----------------------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS metadata.TR_TaskRun_ID_SEQ START 1 INCREMENT 1;
CREATE TABLE IF NOT EXISTS metadata.TR_TaskRun (
    TR_ID int default metadata.TR_TaskRun_ID_SEQ.nextval not null, 
    constraint pkTR_TaskRun primary key (
        TR_ID
    )
) CLUSTER BY (TR_ID);
-- Anchor table -------------------------------------------------------------------------------------------------------
-- CO_Container table (with 3 attributes)
-----------------------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS metadata.CO_Container_ID_SEQ START 1 INCREMENT 1;
CREATE TABLE IF NOT EXISTS metadata.CO_Container (
    CO_ID int default metadata.CO_Container_ID_SEQ.nextval not null, 
    constraint pkCO_Container primary key (
        CO_ID
    )
) CLUSTER BY (CO_ID);
-- Anchor table -------------------------------------------------------------------------------------------------------
-- CF_Configuration table (with 3 attributes)
-----------------------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS metadata.CF_Configuration_ID_SEQ START 1 INCREMENT 1;
CREATE TABLE IF NOT EXISTS metadata.CF_Configuration (
    CF_ID int default metadata.CF_Configuration_ID_SEQ.nextval not null, 
    constraint pkCF_Configuration primary key (
        CF_ID
    )
) CLUSTER BY (CF_ID);
-- Anchor table -------------------------------------------------------------------------------------------------------
-- TP_Template table (with 2 attributes)
-----------------------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS metadata.TP_Template_ID_SEQ START 1 INCREMENT 1;
CREATE TABLE IF NOT EXISTS metadata.TP_Template (
    TP_ID int default metadata.TP_Template_ID_SEQ.nextval not null, 
    constraint pkTP_Template primary key (
        TP_ID
    )
) CLUSTER BY (TP_ID);
-- Anchor table -------------------------------------------------------------------------------------------------------
-- OP_Operations table (with 4 attributes)
-----------------------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS metadata.OP_Operations_ID_SEQ START 1 INCREMENT 1;
CREATE TABLE IF NOT EXISTS metadata.OP_Operations (
    OP_ID int default metadata.OP_Operations_ID_SEQ.nextval not null, 
    constraint pkOP_Operations primary key (
        OP_ID
    )
) CLUSTER BY (OP_ID);
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
CREATE TABLE IF NOT EXISTS metadata.TR_NAM_TaskRun_TaskName (
    TR_NAM_TR_ID int not null,
    TR_NAM_TKN_ID int not null,
    constraint fk_A_TR_NAM_TaskRun_TaskName foreign key (
        TR_NAM_TR_ID
    ) references metadata.TR_TaskRun(TR_ID),
    constraint fk_K_TR_NAM_TaskRun_TaskName foreign key (
        TR_NAM_TKN_ID
    ) references metadata.TKN_TaskName(TKN_ID),
    constraint pkTR_NAM_TaskRun_TaskName primary key (
        TR_NAM_TR_ID
    )
) CLUSTER BY (TR_NAM_TR_ID);
-- Knotted static attribute table -------------------------------------------------------------------------------------
-- TR_GRG_TaskRun_GraphRunGroupId table (on TR_TaskRun)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata.TR_GRG_TaskRun_GraphRunGroupId (
    TR_GRG_TR_ID int not null,
    TR_GRG_GRG_ID int not null,
    constraint fk_A_TR_GRG_TaskRun_GraphRunGroupId foreign key (
        TR_GRG_TR_ID
    ) references metadata.TR_TaskRun(TR_ID),
    constraint fk_K_TR_GRG_TaskRun_GraphRunGroupId foreign key (
        TR_GRG_GRG_ID
    ) references metadata.GRG_GraphRunGroupId(GRG_ID),
    constraint pkTR_GRG_TaskRun_GraphRunGroupId primary key (
        TR_GRG_TR_ID
    )
) CLUSTER BY (TR_GRG_TR_ID);
-- Static attribute table ---------------------------------------------------------------------------------------------
-- CO_NAM_Container_Name table (on CO_Container)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata.CO_NAM_Container_Name (
    CO_NAM_CO_ID int not null,
    CO_NAM_Container_Name varchar(2000) not null,
    constraint fkCO_NAM_Container_Name foreign key (
        CO_NAM_CO_ID
    ) references metadata.CO_Container(CO_ID),
    constraint pkCO_NAM_Container_Name primary key (
        CO_NAM_CO_ID
    )
) CLUSTER BY (CO_NAM_CO_ID);
-- Knotted static attribute table -------------------------------------------------------------------------------------
-- CO_TYP_Container_Type table (on CO_Container)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata.CO_TYP_Container_Type (
    CO_TYP_CO_ID int not null,
    CO_TYP_COT_ID tinyint not null,
    constraint fk_A_CO_TYP_Container_Type foreign key (
        CO_TYP_CO_ID
    ) references metadata.CO_Container(CO_ID),
    constraint fk_K_CO_TYP_Container_Type foreign key (
        CO_TYP_COT_ID
    ) references metadata.COT_ContainerType(COT_ID),
    constraint pkCO_TYP_Container_Type primary key (
        CO_TYP_CO_ID
    )
) CLUSTER BY (CO_TYP_CO_ID);
-- Historized attribute table -----------------------------------------------------------------------------------------
-- CO_DSC_Container_Discovered table (on CO_Container)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata.CO_DSC_Container_Discovered (
    CO_DSC_CO_ID int not null,
    CO_DSC_Container_Discovered timestamp_tz not null,
    CO_DSC_ChangedAt timestamp_tz not null,
    constraint fkCO_DSC_Container_Discovered foreign key (
        CO_DSC_CO_ID
    ) references metadata.CO_Container(CO_ID),
    constraint pkCO_DSC_Container_Discovered primary key (
        CO_DSC_CO_ID,
        CO_DSC_ChangedAt
    )
) CLUSTER BY (CO_DSC_CO_ID, CO_DSC_ChangedAt);
-- Static attribute table ---------------------------------------------------------------------------------------------
-- CF_NAM_Configuration_Name table (on CF_Configuration)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata.CF_NAM_Configuration_Name (
    CF_NAM_CF_ID int not null,
    CF_NAM_Configuration_Name varchar(255) not null,
    constraint fkCF_NAM_Configuration_Name foreign key (
        CF_NAM_CF_ID
    ) references metadata.CF_Configuration(CF_ID),
    constraint pkCF_NAM_Configuration_Name primary key (
        CF_NAM_CF_ID
    )
) CLUSTER BY (CF_NAM_CF_ID);
-- Historized attribute table -----------------------------------------------------------------------------------------
-- CF_CNT_Configuration_Content table (on CF_Configuration)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata.CF_CNT_Configuration_Content (
    CF_CNT_CF_ID int not null,
    CF_CNT_Configuration_Content varchar(16777216) not null,
    CF_CNT_Checksum numeric(19,0) default hash(CF_CNT_Configuration_Content),
    CF_CNT_ChangedAt timestamp_tz not null,
    constraint fkCF_CNT_Configuration_Content foreign key (
        CF_CNT_CF_ID
    ) references metadata.CF_Configuration(CF_ID),
    constraint pkCF_CNT_Configuration_Content primary key (
        CF_CNT_CF_ID,
        CF_CNT_ChangedAt
    )
) CLUSTER BY (CF_CNT_CF_ID, CF_CNT_ChangedAt);
-- Knotted static attribute table -------------------------------------------------------------------------------------
-- CF_TYP_Configuration_Type table (on CF_Configuration)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata.CF_TYP_Configuration_Type (
    CF_TYP_CF_ID int not null,
    CF_TYP_CFT_ID tinyint not null,
    constraint fk_A_CF_TYP_Configuration_Type foreign key (
        CF_TYP_CF_ID
    ) references metadata.CF_Configuration(CF_ID),
    constraint fk_K_CF_TYP_Configuration_Type foreign key (
        CF_TYP_CFT_ID
    ) references metadata.CFT_ConfigurationType(CFT_ID),
    constraint pkCF_TYP_Configuration_Type primary key (
        CF_TYP_CF_ID
    )
) CLUSTER BY (CF_TYP_CF_ID);
-- Static attribute table ---------------------------------------------------------------------------------------------
-- TP_NAM_Template_Name table (on TP_Template)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata.TP_NAM_Template_Name (
    TP_NAM_TP_ID int not null,
    TP_NAM_Template_Name varchar(255) not null,
    constraint fkTP_NAM_Template_Name foreign key (
        TP_NAM_TP_ID
    ) references metadata.TP_Template(TP_ID),
    constraint pkTP_NAM_Template_Name primary key (
        TP_NAM_TP_ID
    )
) CLUSTER BY (TP_NAM_TP_ID);
-- Historized attribute table -----------------------------------------------------------------------------------------
-- TP_CNT_Template_Content table (on TP_Template)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata.TP_CNT_Template_Content (
    TP_CNT_TP_ID int not null,
    TP_CNT_Template_Content varchar(16777216) not null,
    TP_CNT_Checksum numeric(19,0) default hash(TP_CNT_Template_Content),
    TP_CNT_ChangedAt timestamp_tz not null,
    constraint fkTP_CNT_Template_Content foreign key (
        TP_CNT_TP_ID
    ) references metadata.TP_Template(TP_ID),
    constraint pkTP_CNT_Template_Content primary key (
        TP_CNT_TP_ID,
        TP_CNT_ChangedAt
    )
) CLUSTER BY (TP_CNT_TP_ID, TP_CNT_ChangedAt);
-- Historized attribute table -----------------------------------------------------------------------------------------
-- OP_INS_Operations_RowsInserted table (on OP_Operations)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata.OP_INS_Operations_RowsInserted (
    OP_INS_OP_ID int not null,
    OP_INS_Operations_RowsInserted int not null,
    OP_INS_ChangedAt timestamp_tz not null,
    constraint fkOP_INS_Operations_RowsInserted foreign key (
        OP_INS_OP_ID
    ) references metadata.OP_Operations(OP_ID),
    constraint pkOP_INS_Operations_RowsInserted primary key (
        OP_INS_OP_ID,
        OP_INS_ChangedAt
    )
) CLUSTER BY (OP_INS_OP_ID, OP_INS_ChangedAt);
-- Historized attribute table -----------------------------------------------------------------------------------------
-- OP_UPD_Operations_RowsUpdated table (on OP_Operations)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata.OP_UPD_Operations_RowsUpdated (
    OP_UPD_OP_ID int not null,
    OP_UPD_Operations_RowsUpdated int not null,
    OP_UPD_ChangedAt timestamp_tz not null,
    constraint fkOP_UPD_Operations_RowsUpdated foreign key (
        OP_UPD_OP_ID
    ) references metadata.OP_Operations(OP_ID),
    constraint pkOP_UPD_Operations_RowsUpdated primary key (
        OP_UPD_OP_ID,
        OP_UPD_ChangedAt
    )
) CLUSTER BY (OP_UPD_OP_ID, OP_UPD_ChangedAt);
-- Historized attribute table -----------------------------------------------------------------------------------------
-- OP_DEL_Operations_RowsDeleted table (on OP_Operations)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata.OP_DEL_Operations_RowsDeleted (
    OP_DEL_OP_ID int not null,
    OP_DEL_Operations_RowsDeleted int not null,
    OP_DEL_ChangedAt timestamp_tz not null,
    constraint fkOP_DEL_Operations_RowsDeleted foreign key (
        OP_DEL_OP_ID
    ) references metadata.OP_Operations(OP_ID),
    constraint pkOP_DEL_Operations_RowsDeleted primary key (
        OP_DEL_OP_ID,
        OP_DEL_ChangedAt
    )
) CLUSTER BY (OP_DEL_OP_ID, OP_DEL_ChangedAt);
-- Historized attribute table -----------------------------------------------------------------------------------------
-- OP_MRG_Operations_RowsMerged table (on OP_Operations)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata.OP_MRG_Operations_RowsMerged (
    OP_MRG_OP_ID int not null,
    OP_MRG_Operations_RowsMerged int not null,
    OP_MRG_ChangedAt timestamp_tz not null,
    constraint fkOP_MRG_Operations_RowsMerged foreign key (
        OP_MRG_OP_ID
    ) references metadata.OP_Operations(OP_ID),
    constraint pkOP_MRG_Operations_RowsMerged primary key (
        OP_MRG_OP_ID,
        OP_MRG_ChangedAt
    )
) CLUSTER BY (OP_MRG_OP_ID, OP_MRG_ChangedAt);
-- TIES ---------------------------------------------------------------------------------------------------------------
--
-- Ties are used to represent relationships between entities.
-- They come in four flavors: static, historized, knotted static, and knotted historized.
-- Ties have cardinality, constraining how members may participate in the relationship.
-- Every entity that is a member in a tie has a specified role in the relationship.
-- Ties must have at least two anchor roles and zero or more knot roles.
--
-- Knotted static tie table -------------------------------------------------------------------------------------------
-- TR_operates_CO_source_CO_target_OP_with table (having 4 roles)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata.TR_operates_CO_source_CO_target_OP_with (
    TR_ID_operates int not null, 
    CO_ID_source int not null, 
    CO_ID_target int not null, 
    OP_ID_with int not null, 
    constraint TR_operates_CO_source_CO_target_OP_with_fkTR_operates foreign key (
        TR_ID_operates
    ) references metadata.TR_TaskRun(TR_ID), 
    constraint TR_operates_CO_source_CO_target_OP_with_fkCO_source foreign key (
        CO_ID_source
    ) references metadata.CO_Container(CO_ID), 
    constraint TR_operates_CO_source_CO_target_OP_with_fkCO_target foreign key (
        CO_ID_target
    ) references metadata.CO_Container(CO_ID), 
    constraint TR_operates_CO_source_CO_target_OP_with_fkOP_with foreign key (
        OP_ID_with
    ) references metadata.OP_Operations(OP_ID), 
    constraint pkTR_operates_CO_source_CO_target_OP_with primary key (
        TR_ID_operates,
        CO_ID_source,
        CO_ID_target
    )
) CLUSTER BY (
    TR_ID_operates,
    CO_ID_source,
    CO_ID_target,
    OP_ID_with
);
-- Knotted static tie table -------------------------------------------------------------------------------------------
-- TR_formed_CF_from table (having 2 roles)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata.TR_formed_CF_from (
    TR_ID_formed int not null, 
    CF_ID_from int not null, 
    constraint TR_formed_CF_from_fkTR_formed foreign key (
        TR_ID_formed
    ) references metadata.TR_TaskRun(TR_ID), 
    constraint TR_formed_CF_from_fkCF_from foreign key (
        CF_ID_from
    ) references metadata.CF_Configuration(CF_ID), 
    constraint pkTR_formed_CF_from primary key (
        TR_ID_formed
    )
) CLUSTER BY (
    TR_ID_formed,
    CF_ID_from
);
-- Knotted static tie table -------------------------------------------------------------------------------------------
-- CF_uses_TP_template table (having 2 roles)
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metadata.CF_uses_TP_template (
    CF_ID_uses int not null, 
    TP_ID_template int not null, 
    constraint CF_uses_TP_template_fkCF_uses foreign key (
        CF_ID_uses
    ) references metadata.CF_Configuration(CF_ID), 
    constraint CF_uses_TP_template_fkTP_template foreign key (
        TP_ID_template
    ) references metadata.TP_Template(TP_ID), 
    constraint pkCF_uses_TP_template primary key (
        CF_ID_uses
    )
) CLUSTER BY (
    CF_ID_uses,
    TP_ID_template
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
CREATE OR REPLACE FUNCTION metadata.rCO_DSC_Container_Discovered (
    changingTimepoint timestamp_tz
)
RETURNS TABLE (
    CO_DSC_CO_ID int,
    CO_DSC_Container_Discovered timestamp_tz,
    CO_DSC_ChangedAt timestamp_tz
)
AS
$$
    SELECT
        CO_DSC_CO_ID,
        CO_DSC_Container_Discovered,
        CO_DSC_ChangedAt
    FROM
        metadata.CO_DSC_Container_Discovered
    WHERE
        CO_DSC_ChangedAt <= changingTimepoint
$$
;
-- Attribute rewinder -------------------------------------------------------------------------------------------------
-- rCF_CNT_Configuration_Content rewinding over changing time function
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata.rCF_CNT_Configuration_Content (
    changingTimepoint timestamp_tz
)
RETURNS TABLE (
    CF_CNT_CF_ID int,
    CF_CNT_Checksum numeric(19,0),
    CF_CNT_Configuration_Content varchar(16777216),
    CF_CNT_ChangedAt timestamp_tz
)
AS
$$
    SELECT
        CF_CNT_CF_ID,
        CF_CNT_Checksum,
        CF_CNT_Configuration_Content,
        CF_CNT_ChangedAt
    FROM
        metadata.CF_CNT_Configuration_Content
    WHERE
        CF_CNT_ChangedAt <= changingTimepoint
$$
;
-- Attribute rewinder -------------------------------------------------------------------------------------------------
-- rTP_CNT_Template_Content rewinding over changing time function
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata.rTP_CNT_Template_Content (
    changingTimepoint timestamp_tz
)
RETURNS TABLE (
    TP_CNT_TP_ID int,
    TP_CNT_Checksum numeric(19,0),
    TP_CNT_Template_Content varchar(16777216),
    TP_CNT_ChangedAt timestamp_tz
)
AS
$$
    SELECT
        TP_CNT_TP_ID,
        TP_CNT_Checksum,
        TP_CNT_Template_Content,
        TP_CNT_ChangedAt
    FROM
        metadata.TP_CNT_Template_Content
    WHERE
        TP_CNT_ChangedAt <= changingTimepoint
$$
;
-- Attribute rewinder -------------------------------------------------------------------------------------------------
-- rOP_INS_Operations_RowsInserted rewinding over changing time function
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata.rOP_INS_Operations_RowsInserted (
    changingTimepoint timestamp_tz
)
RETURNS TABLE (
    OP_INS_OP_ID int,
    OP_INS_Operations_RowsInserted int,
    OP_INS_ChangedAt timestamp_tz
)
AS
$$
    SELECT
        OP_INS_OP_ID,
        OP_INS_Operations_RowsInserted,
        OP_INS_ChangedAt
    FROM
        metadata.OP_INS_Operations_RowsInserted
    WHERE
        OP_INS_ChangedAt <= changingTimepoint
$$
;
-- Attribute rewinder -------------------------------------------------------------------------------------------------
-- rOP_UPD_Operations_RowsUpdated rewinding over changing time function
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata.rOP_UPD_Operations_RowsUpdated (
    changingTimepoint timestamp_tz
)
RETURNS TABLE (
    OP_UPD_OP_ID int,
    OP_UPD_Operations_RowsUpdated int,
    OP_UPD_ChangedAt timestamp_tz
)
AS
$$
    SELECT
        OP_UPD_OP_ID,
        OP_UPD_Operations_RowsUpdated,
        OP_UPD_ChangedAt
    FROM
        metadata.OP_UPD_Operations_RowsUpdated
    WHERE
        OP_UPD_ChangedAt <= changingTimepoint
$$
;
-- Attribute rewinder -------------------------------------------------------------------------------------------------
-- rOP_DEL_Operations_RowsDeleted rewinding over changing time function
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata.rOP_DEL_Operations_RowsDeleted (
    changingTimepoint timestamp_tz
)
RETURNS TABLE (
    OP_DEL_OP_ID int,
    OP_DEL_Operations_RowsDeleted int,
    OP_DEL_ChangedAt timestamp_tz
)
AS
$$
    SELECT
        OP_DEL_OP_ID,
        OP_DEL_Operations_RowsDeleted,
        OP_DEL_ChangedAt
    FROM
        metadata.OP_DEL_Operations_RowsDeleted
    WHERE
        OP_DEL_ChangedAt <= changingTimepoint
$$
;
-- Attribute rewinder -------------------------------------------------------------------------------------------------
-- rOP_MRG_Operations_RowsMerged rewinding over changing time function
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata.rOP_MRG_Operations_RowsMerged (
    changingTimepoint timestamp_tz
)
RETURNS TABLE (
    OP_MRG_OP_ID int,
    OP_MRG_Operations_RowsMerged int,
    OP_MRG_ChangedAt timestamp_tz
)
AS
$$
    SELECT
        OP_MRG_OP_ID,
        OP_MRG_Operations_RowsMerged,
        OP_MRG_ChangedAt
    FROM
        metadata.OP_MRG_Operations_RowsMerged
    WHERE
        OP_MRG_ChangedAt <= changingTimepoint
$$
;
-- ANCHOR TEMPORAL PERSPECTIVES ---------------------------------------------------------------------------------------
--
-- Snowflake-native anchor perspectives: latest (l), point-in-time (p), now (n), difference (d),
-- and their equivalence variants (el, ep, en, ed).
--
-- Latest perspective -------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata.lTR_TaskRun AS
SELECT
    TR.TR_ID,
    NAM.TR_NAM_TR_ID,
    kNAM.TKN_TaskName AS TR_NAM_TKN_TaskName,
    NAM.TR_NAM_TKN_ID,
    GRG.TR_GRG_TR_ID,
    kGRG.GRG_GraphRunGroupId AS TR_GRG_GRG_GraphRunGroupId,
    GRG.TR_GRG_GRG_ID
FROM
    metadata.TR_TaskRun TR
LEFT JOIN
    metadata.TR_NAM_TaskRun_TaskName NAM
ON
    NAM.TR_NAM_TR_ID = TR.TR_ID
LEFT JOIN
    metadata.TKN_TaskName kNAM
ON
    kNAM.TKN_ID = NAM.TR_NAM_TKN_ID
LEFT JOIN
    metadata.TR_GRG_TaskRun_GraphRunGroupId GRG
ON
    GRG.TR_GRG_TR_ID = TR.TR_ID
LEFT JOIN
    metadata.GRG_GraphRunGroupId kGRG
ON
    kGRG.GRG_ID = GRG.TR_GRG_GRG_ID;
-- Point-in-time perspective ------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata.pTR_TaskRun (
    changingTimepoint timestamp_tz
)
RETURNS TABLE (
    TR_ID int,
    TR_NAM_TR_ID int,
    TR_NAM_TKN_TaskName varchar(500),
    TR_NAM_TKN_ID int,
    TR_GRG_TR_ID int,
    TR_GRG_GRG_GraphRunGroupId varchar(100),
    TR_GRG_GRG_ID int
)
AS
$$
SELECT
    TR.TR_ID,
    NAM.TR_NAM_TR_ID,
    kNAM.TKN_TaskName AS TR_NAM_TKN_TaskName,
    NAM.TR_NAM_TKN_ID,
    GRG.TR_GRG_TR_ID,
    kGRG.GRG_GraphRunGroupId AS TR_GRG_GRG_GraphRunGroupId,
    GRG.TR_GRG_GRG_ID
FROM
    metadata.TR_TaskRun TR
LEFT JOIN
    metadata.TR_NAM_TaskRun_TaskName NAM
ON
    NAM.TR_NAM_TR_ID = TR.TR_ID
LEFT JOIN
    metadata.TKN_TaskName kNAM
ON
    kNAM.TKN_ID = NAM.TR_NAM_TKN_ID
LEFT JOIN
    metadata.TR_GRG_TaskRun_GraphRunGroupId GRG
ON
    GRG.TR_GRG_TR_ID = TR.TR_ID
LEFT JOIN
    metadata.GRG_GraphRunGroupId kGRG
ON
    kGRG.GRG_ID = GRG.TR_GRG_GRG_ID
$$
;
-- Now perspective ----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata.nTR_TaskRun
AS
SELECT
    *
FROM
    TABLE(metadata.pTR_TaskRun(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)::timestamp_tz))
;
-- Latest perspective -------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata.lCO_Container AS
SELECT
    CO.CO_ID,
    NAM.CO_NAM_CO_ID,
    NAM.CO_NAM_Container_Name,
    TYP.CO_TYP_CO_ID,
    kTYP.COT_ContainerType AS CO_TYP_COT_ContainerType,
    TYP.CO_TYP_COT_ID,
    DSC.CO_DSC_CO_ID,
    DSC.CO_DSC_ChangedAt,
    DSC.CO_DSC_Container_Discovered
FROM
    metadata.CO_Container CO
LEFT JOIN
    metadata.CO_NAM_Container_Name NAM
ON
    NAM.CO_NAM_CO_ID = CO.CO_ID
LEFT JOIN
    metadata.CO_TYP_Container_Type TYP
ON
    TYP.CO_TYP_CO_ID = CO.CO_ID
LEFT JOIN
    metadata.COT_ContainerType kTYP
ON
    kTYP.COT_ID = TYP.CO_TYP_COT_ID
LEFT JOIN
    metadata.CO_DSC_Container_Discovered DSC
ON
    DSC.CO_DSC_CO_ID = CO.CO_ID
AND
    DSC.CO_DSC_ChangedAt = (
        SELECT
            max(sub.CO_DSC_ChangedAt)
        FROM
            metadata.CO_DSC_Container_Discovered sub
        WHERE
            sub.CO_DSC_CO_ID = CO.CO_ID
   );
-- Point-in-time perspective ------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata.pCO_Container (
    changingTimepoint timestamp_tz
)
RETURNS TABLE (
    CO_ID int,
    CO_NAM_CO_ID int,
    CO_NAM_Container_Name varchar(2000),
    CO_TYP_CO_ID int,
    CO_TYP_COT_ContainerType varchar(42),
    CO_TYP_COT_ID tinyint,
    CO_DSC_CO_ID int,
    CO_DSC_ChangedAt timestamp_tz,
    CO_DSC_Container_Discovered timestamp_tz
)
AS
$$
SELECT
    CO.CO_ID,
    NAM.CO_NAM_CO_ID,
    NAM.CO_NAM_Container_Name,
    TYP.CO_TYP_CO_ID,
    kTYP.COT_ContainerType AS CO_TYP_COT_ContainerType,
    TYP.CO_TYP_COT_ID,
    DSC.CO_DSC_CO_ID,
    DSC.CO_DSC_ChangedAt,
    DSC.CO_DSC_Container_Discovered
FROM
    metadata.CO_Container CO
LEFT JOIN
    metadata.CO_NAM_Container_Name NAM
ON
    NAM.CO_NAM_CO_ID = CO.CO_ID
LEFT JOIN
    metadata.CO_TYP_Container_Type TYP
ON
    TYP.CO_TYP_CO_ID = CO.CO_ID
LEFT JOIN
    metadata.COT_ContainerType kTYP
ON
    kTYP.COT_ID = TYP.CO_TYP_COT_ID
LEFT JOIN
    TABLE(metadata.rCO_DSC_Container_Discovered(changingTimepoint::timestamp_tz)) DSC
ON
    DSC.CO_DSC_CO_ID = CO.CO_ID
AND
    DSC.CO_DSC_ChangedAt = (
        SELECT
            max(sub.CO_DSC_ChangedAt)
        FROM
            TABLE(metadata.rCO_DSC_Container_Discovered(changingTimepoint::timestamp_tz)) sub
        WHERE
            sub.CO_DSC_CO_ID = CO.CO_ID
   )
$$
;
-- Now perspective ----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata.nCO_Container
AS
SELECT
    *
FROM
    TABLE(metadata.pCO_Container(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)::timestamp_tz))
;
-- Difference perspective ---------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata.dCO_Container (
    intervalStart timestamp_tz,
    intervalEnd timestamp_tz,
    selection string
)
RETURNS TABLE (
    inspectedTimepoint timestamp_tz,
    mnemonic string,
    CO_ID int,
    CO_NAM_CO_ID int,
    CO_NAM_Container_Name varchar(2000),
    CO_TYP_CO_ID int,
    CO_TYP_COT_ContainerType varchar(42),
    CO_TYP_COT_ID tinyint,
    CO_DSC_CO_ID int,
    CO_DSC_ChangedAt timestamp_tz,
    CO_DSC_Container_Discovered timestamp_tz
)
AS
$$
SELECT DISTINCT
    hDSC.CO_DSC_ChangedAt::timestamp_tz AS inspectedTimepoint,
    'DSC' AS mnemonic,
    pCO.CO_ID,
    pCO.CO_NAM_CO_ID,
    pCO.CO_NAM_Container_Name,
    pCO.CO_TYP_CO_ID,
    pCO.CO_TYP_COT_ContainerType,
    pCO.CO_TYP_COT_ID,
    pCO.CO_DSC_CO_ID,
    pCO.CO_DSC_ChangedAt,
    pCO.CO_DSC_Container_Discovered
FROM
    metadata.CO_DSC_Container_Discovered hDSC,
    TABLE(metadata.pCO_Container(hDSC.CO_DSC_ChangedAt::timestamp_tz)) pCO
WHERE
    (selection IS NULL OR selection LIKE '%DSC%')
AND
    hDSC.CO_DSC_ChangedAt BETWEEN intervalStart AND intervalEnd
AND
    pCO.CO_ID = hDSC.CO_DSC_CO_ID
$$
;
-- Latest perspective -------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata.lCF_Configuration AS
SELECT
    CF.CF_ID,
    NAM.CF_NAM_CF_ID,
    NAM.CF_NAM_Configuration_Name,
    CNT.CF_CNT_CF_ID,
    CNT.CF_CNT_ChangedAt,
    CNT.CF_CNT_Checksum,
    CNT.CF_CNT_Configuration_Content,
    TYP.CF_TYP_CF_ID,
    kTYP.CFT_ConfigurationType AS CF_TYP_CFT_ConfigurationType,
    TYP.CF_TYP_CFT_ID
FROM
    metadata.CF_Configuration CF
LEFT JOIN
    metadata.CF_NAM_Configuration_Name NAM
ON
    NAM.CF_NAM_CF_ID = CF.CF_ID
LEFT JOIN
    metadata.CF_CNT_Configuration_Content CNT
ON
    CNT.CF_CNT_CF_ID = CF.CF_ID
AND
    CNT.CF_CNT_ChangedAt = (
        SELECT
            max(sub.CF_CNT_ChangedAt)
        FROM
            metadata.CF_CNT_Configuration_Content sub
        WHERE
            sub.CF_CNT_CF_ID = CF.CF_ID
   )
LEFT JOIN
    metadata.CF_TYP_Configuration_Type TYP
ON
    TYP.CF_TYP_CF_ID = CF.CF_ID
LEFT JOIN
    metadata.CFT_ConfigurationType kTYP
ON
    kTYP.CFT_ID = TYP.CF_TYP_CFT_ID;
-- Point-in-time perspective ------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata.pCF_Configuration (
    changingTimepoint timestamp_tz
)
RETURNS TABLE (
    CF_ID int,
    CF_NAM_CF_ID int,
    CF_NAM_Configuration_Name varchar(255),
    CF_CNT_CF_ID int,
    CF_CNT_ChangedAt timestamp_tz,
    CF_CNT_Checksum numeric(19,0),
    CF_CNT_Configuration_Content varchar(16777216),
    CF_TYP_CF_ID int,
    CF_TYP_CFT_ConfigurationType varchar(42),
    CF_TYP_CFT_ID tinyint
)
AS
$$
SELECT
    CF.CF_ID,
    NAM.CF_NAM_CF_ID,
    NAM.CF_NAM_Configuration_Name,
    CNT.CF_CNT_CF_ID,
    CNT.CF_CNT_ChangedAt,
    CNT.CF_CNT_Checksum,
    CNT.CF_CNT_Configuration_Content,
    TYP.CF_TYP_CF_ID,
    kTYP.CFT_ConfigurationType AS CF_TYP_CFT_ConfigurationType,
    TYP.CF_TYP_CFT_ID
FROM
    metadata.CF_Configuration CF
LEFT JOIN
    metadata.CF_NAM_Configuration_Name NAM
ON
    NAM.CF_NAM_CF_ID = CF.CF_ID
LEFT JOIN
    TABLE(metadata.rCF_CNT_Configuration_Content(changingTimepoint::timestamp_tz)) CNT
ON
    CNT.CF_CNT_CF_ID = CF.CF_ID
AND
    CNT.CF_CNT_ChangedAt = (
        SELECT
            max(sub.CF_CNT_ChangedAt)
        FROM
            TABLE(metadata.rCF_CNT_Configuration_Content(changingTimepoint::timestamp_tz)) sub
        WHERE
            sub.CF_CNT_CF_ID = CF.CF_ID
   )
LEFT JOIN
    metadata.CF_TYP_Configuration_Type TYP
ON
    TYP.CF_TYP_CF_ID = CF.CF_ID
LEFT JOIN
    metadata.CFT_ConfigurationType kTYP
ON
    kTYP.CFT_ID = TYP.CF_TYP_CFT_ID
$$
;
-- Now perspective ----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata.nCF_Configuration
AS
SELECT
    *
FROM
    TABLE(metadata.pCF_Configuration(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)::timestamp_tz))
;
-- Difference perspective ---------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata.dCF_Configuration (
    intervalStart timestamp_tz,
    intervalEnd timestamp_tz,
    selection string
)
RETURNS TABLE (
    inspectedTimepoint timestamp_tz,
    mnemonic string,
    CF_ID int,
    CF_NAM_CF_ID int,
    CF_NAM_Configuration_Name varchar(255),
    CF_CNT_CF_ID int,
    CF_CNT_ChangedAt timestamp_tz,
    CF_CNT_Checksum numeric(19,0),
    CF_CNT_Configuration_Content varchar(16777216),
    CF_TYP_CF_ID int,
    CF_TYP_CFT_ConfigurationType varchar(42),
    CF_TYP_CFT_ID tinyint
)
AS
$$
SELECT DISTINCT
    hCNT.CF_CNT_ChangedAt::timestamp_tz AS inspectedTimepoint,
    'CNT' AS mnemonic,
    pCF.CF_ID,
    pCF.CF_NAM_CF_ID,
    pCF.CF_NAM_Configuration_Name,
    pCF.CF_CNT_CF_ID,
    pCF.CF_CNT_ChangedAt,
    pCF.CF_CNT_Checksum,
    pCF.CF_CNT_Configuration_Content,
    pCF.CF_TYP_CF_ID,
    pCF.CF_TYP_CFT_ConfigurationType,
    pCF.CF_TYP_CFT_ID
FROM
    metadata.CF_CNT_Configuration_Content hCNT,
    TABLE(metadata.pCF_Configuration(hCNT.CF_CNT_ChangedAt::timestamp_tz)) pCF
WHERE
    (selection IS NULL OR selection LIKE '%CNT%')
AND
    hCNT.CF_CNT_ChangedAt BETWEEN intervalStart AND intervalEnd
AND
    pCF.CF_ID = hCNT.CF_CNT_CF_ID
$$
;
-- Latest perspective -------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata.lTP_Template AS
SELECT
    TP.TP_ID,
    NAM.TP_NAM_TP_ID,
    NAM.TP_NAM_Template_Name,
    CNT.TP_CNT_TP_ID,
    CNT.TP_CNT_ChangedAt,
    CNT.TP_CNT_Checksum,
    CNT.TP_CNT_Template_Content
FROM
    metadata.TP_Template TP
LEFT JOIN
    metadata.TP_NAM_Template_Name NAM
ON
    NAM.TP_NAM_TP_ID = TP.TP_ID
LEFT JOIN
    metadata.TP_CNT_Template_Content CNT
ON
    CNT.TP_CNT_TP_ID = TP.TP_ID
AND
    CNT.TP_CNT_ChangedAt = (
        SELECT
            max(sub.TP_CNT_ChangedAt)
        FROM
            metadata.TP_CNT_Template_Content sub
        WHERE
            sub.TP_CNT_TP_ID = TP.TP_ID
   );
-- Point-in-time perspective ------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata.pTP_Template (
    changingTimepoint timestamp_tz
)
RETURNS TABLE (
    TP_ID int,
    TP_NAM_TP_ID int,
    TP_NAM_Template_Name varchar(255),
    TP_CNT_TP_ID int,
    TP_CNT_ChangedAt timestamp_tz,
    TP_CNT_Checksum numeric(19,0),
    TP_CNT_Template_Content varchar(16777216)
)
AS
$$
SELECT
    TP.TP_ID,
    NAM.TP_NAM_TP_ID,
    NAM.TP_NAM_Template_Name,
    CNT.TP_CNT_TP_ID,
    CNT.TP_CNT_ChangedAt,
    CNT.TP_CNT_Checksum,
    CNT.TP_CNT_Template_Content
FROM
    metadata.TP_Template TP
LEFT JOIN
    metadata.TP_NAM_Template_Name NAM
ON
    NAM.TP_NAM_TP_ID = TP.TP_ID
LEFT JOIN
    TABLE(metadata.rTP_CNT_Template_Content(changingTimepoint::timestamp_tz)) CNT
ON
    CNT.TP_CNT_TP_ID = TP.TP_ID
AND
    CNT.TP_CNT_ChangedAt = (
        SELECT
            max(sub.TP_CNT_ChangedAt)
        FROM
            TABLE(metadata.rTP_CNT_Template_Content(changingTimepoint::timestamp_tz)) sub
        WHERE
            sub.TP_CNT_TP_ID = TP.TP_ID
   )
$$
;
-- Now perspective ----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata.nTP_Template
AS
SELECT
    *
FROM
    TABLE(metadata.pTP_Template(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)::timestamp_tz))
;
-- Difference perspective ---------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata.dTP_Template (
    intervalStart timestamp_tz,
    intervalEnd timestamp_tz,
    selection string
)
RETURNS TABLE (
    inspectedTimepoint timestamp_tz,
    mnemonic string,
    TP_ID int,
    TP_NAM_TP_ID int,
    TP_NAM_Template_Name varchar(255),
    TP_CNT_TP_ID int,
    TP_CNT_ChangedAt timestamp_tz,
    TP_CNT_Checksum numeric(19,0),
    TP_CNT_Template_Content varchar(16777216)
)
AS
$$
SELECT DISTINCT
    hCNT.TP_CNT_ChangedAt::timestamp_tz AS inspectedTimepoint,
    'CNT' AS mnemonic,
    pTP.TP_ID,
    pTP.TP_NAM_TP_ID,
    pTP.TP_NAM_Template_Name,
    pTP.TP_CNT_TP_ID,
    pTP.TP_CNT_ChangedAt,
    pTP.TP_CNT_Checksum,
    pTP.TP_CNT_Template_Content
FROM
    metadata.TP_CNT_Template_Content hCNT,
    TABLE(metadata.pTP_Template(hCNT.TP_CNT_ChangedAt::timestamp_tz)) pTP
WHERE
    (selection IS NULL OR selection LIKE '%CNT%')
AND
    hCNT.TP_CNT_ChangedAt BETWEEN intervalStart AND intervalEnd
AND
    pTP.TP_ID = hCNT.TP_CNT_TP_ID
$$
;
-- Latest perspective -------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata.lOP_Operations AS
SELECT
    OP.OP_ID,
    INS.OP_INS_OP_ID,
    INS.OP_INS_ChangedAt,
    INS.OP_INS_Operations_RowsInserted,
    UPD.OP_UPD_OP_ID,
    UPD.OP_UPD_ChangedAt,
    UPD.OP_UPD_Operations_RowsUpdated,
    DEL.OP_DEL_OP_ID,
    DEL.OP_DEL_ChangedAt,
    DEL.OP_DEL_Operations_RowsDeleted,
    MRG.OP_MRG_OP_ID,
    MRG.OP_MRG_ChangedAt,
    MRG.OP_MRG_Operations_RowsMerged
FROM
    metadata.OP_Operations OP
LEFT JOIN
    metadata.OP_INS_Operations_RowsInserted INS
ON
    INS.OP_INS_OP_ID = OP.OP_ID
AND
    INS.OP_INS_ChangedAt = (
        SELECT
            max(sub.OP_INS_ChangedAt)
        FROM
            metadata.OP_INS_Operations_RowsInserted sub
        WHERE
            sub.OP_INS_OP_ID = OP.OP_ID
   )
LEFT JOIN
    metadata.OP_UPD_Operations_RowsUpdated UPD
ON
    UPD.OP_UPD_OP_ID = OP.OP_ID
AND
    UPD.OP_UPD_ChangedAt = (
        SELECT
            max(sub.OP_UPD_ChangedAt)
        FROM
            metadata.OP_UPD_Operations_RowsUpdated sub
        WHERE
            sub.OP_UPD_OP_ID = OP.OP_ID
   )
LEFT JOIN
    metadata.OP_DEL_Operations_RowsDeleted DEL
ON
    DEL.OP_DEL_OP_ID = OP.OP_ID
AND
    DEL.OP_DEL_ChangedAt = (
        SELECT
            max(sub.OP_DEL_ChangedAt)
        FROM
            metadata.OP_DEL_Operations_RowsDeleted sub
        WHERE
            sub.OP_DEL_OP_ID = OP.OP_ID
   )
LEFT JOIN
    metadata.OP_MRG_Operations_RowsMerged MRG
ON
    MRG.OP_MRG_OP_ID = OP.OP_ID
AND
    MRG.OP_MRG_ChangedAt = (
        SELECT
            max(sub.OP_MRG_ChangedAt)
        FROM
            metadata.OP_MRG_Operations_RowsMerged sub
        WHERE
            sub.OP_MRG_OP_ID = OP.OP_ID
   );
-- Point-in-time perspective ------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata.pOP_Operations (
    changingTimepoint timestamp_tz
)
RETURNS TABLE (
    OP_ID int,
    OP_INS_OP_ID int,
    OP_INS_ChangedAt timestamp_tz,
    OP_INS_Operations_RowsInserted int,
    OP_UPD_OP_ID int,
    OP_UPD_ChangedAt timestamp_tz,
    OP_UPD_Operations_RowsUpdated int,
    OP_DEL_OP_ID int,
    OP_DEL_ChangedAt timestamp_tz,
    OP_DEL_Operations_RowsDeleted int,
    OP_MRG_OP_ID int,
    OP_MRG_ChangedAt timestamp_tz,
    OP_MRG_Operations_RowsMerged int
)
AS
$$
SELECT
    OP.OP_ID,
    INS.OP_INS_OP_ID,
    INS.OP_INS_ChangedAt,
    INS.OP_INS_Operations_RowsInserted,
    UPD.OP_UPD_OP_ID,
    UPD.OP_UPD_ChangedAt,
    UPD.OP_UPD_Operations_RowsUpdated,
    DEL.OP_DEL_OP_ID,
    DEL.OP_DEL_ChangedAt,
    DEL.OP_DEL_Operations_RowsDeleted,
    MRG.OP_MRG_OP_ID,
    MRG.OP_MRG_ChangedAt,
    MRG.OP_MRG_Operations_RowsMerged
FROM
    metadata.OP_Operations OP
LEFT JOIN
    TABLE(metadata.rOP_INS_Operations_RowsInserted(changingTimepoint::timestamp_tz)) INS
ON
    INS.OP_INS_OP_ID = OP.OP_ID
AND
    INS.OP_INS_ChangedAt = (
        SELECT
            max(sub.OP_INS_ChangedAt)
        FROM
            TABLE(metadata.rOP_INS_Operations_RowsInserted(changingTimepoint::timestamp_tz)) sub
        WHERE
            sub.OP_INS_OP_ID = OP.OP_ID
   )
LEFT JOIN
    TABLE(metadata.rOP_UPD_Operations_RowsUpdated(changingTimepoint::timestamp_tz)) UPD
ON
    UPD.OP_UPD_OP_ID = OP.OP_ID
AND
    UPD.OP_UPD_ChangedAt = (
        SELECT
            max(sub.OP_UPD_ChangedAt)
        FROM
            TABLE(metadata.rOP_UPD_Operations_RowsUpdated(changingTimepoint::timestamp_tz)) sub
        WHERE
            sub.OP_UPD_OP_ID = OP.OP_ID
   )
LEFT JOIN
    TABLE(metadata.rOP_DEL_Operations_RowsDeleted(changingTimepoint::timestamp_tz)) DEL
ON
    DEL.OP_DEL_OP_ID = OP.OP_ID
AND
    DEL.OP_DEL_ChangedAt = (
        SELECT
            max(sub.OP_DEL_ChangedAt)
        FROM
            TABLE(metadata.rOP_DEL_Operations_RowsDeleted(changingTimepoint::timestamp_tz)) sub
        WHERE
            sub.OP_DEL_OP_ID = OP.OP_ID
   )
LEFT JOIN
    TABLE(metadata.rOP_MRG_Operations_RowsMerged(changingTimepoint::timestamp_tz)) MRG
ON
    MRG.OP_MRG_OP_ID = OP.OP_ID
AND
    MRG.OP_MRG_ChangedAt = (
        SELECT
            max(sub.OP_MRG_ChangedAt)
        FROM
            TABLE(metadata.rOP_MRG_Operations_RowsMerged(changingTimepoint::timestamp_tz)) sub
        WHERE
            sub.OP_MRG_OP_ID = OP.OP_ID
   )
$$
;
-- Now perspective ----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata.nOP_Operations
AS
SELECT
    *
FROM
    TABLE(metadata.pOP_Operations(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)::timestamp_tz))
;
-- Difference perspective ---------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata.dOP_Operations (
    intervalStart timestamp_tz,
    intervalEnd timestamp_tz,
    selection string
)
RETURNS TABLE (
    inspectedTimepoint timestamp_tz,
    mnemonic string,
    OP_ID int,
    OP_INS_OP_ID int,
    OP_INS_ChangedAt timestamp_tz,
    OP_INS_Operations_RowsInserted int,
    OP_UPD_OP_ID int,
    OP_UPD_ChangedAt timestamp_tz,
    OP_UPD_Operations_RowsUpdated int,
    OP_DEL_OP_ID int,
    OP_DEL_ChangedAt timestamp_tz,
    OP_DEL_Operations_RowsDeleted int,
    OP_MRG_OP_ID int,
    OP_MRG_ChangedAt timestamp_tz,
    OP_MRG_Operations_RowsMerged int
)
AS
$$
SELECT DISTINCT
    hINS.OP_INS_ChangedAt::timestamp_tz AS inspectedTimepoint,
    'INS' AS mnemonic,
    pOP.OP_ID,
    pOP.OP_INS_OP_ID,
    pOP.OP_INS_ChangedAt,
    pOP.OP_INS_Operations_RowsInserted,
    pOP.OP_UPD_OP_ID,
    pOP.OP_UPD_ChangedAt,
    pOP.OP_UPD_Operations_RowsUpdated,
    pOP.OP_DEL_OP_ID,
    pOP.OP_DEL_ChangedAt,
    pOP.OP_DEL_Operations_RowsDeleted,
    pOP.OP_MRG_OP_ID,
    pOP.OP_MRG_ChangedAt,
    pOP.OP_MRG_Operations_RowsMerged
FROM
    metadata.OP_INS_Operations_RowsInserted hINS,
    TABLE(metadata.pOP_Operations(hINS.OP_INS_ChangedAt::timestamp_tz)) pOP
WHERE
    (selection IS NULL OR selection LIKE '%INS%')
AND
    hINS.OP_INS_ChangedAt BETWEEN intervalStart AND intervalEnd
AND
    pOP.OP_ID = hINS.OP_INS_OP_ID
UNION
SELECT DISTINCT
    hUPD.OP_UPD_ChangedAt::timestamp_tz AS inspectedTimepoint,
    'UPD' AS mnemonic,
    pOP.OP_ID,
    pOP.OP_INS_OP_ID,
    pOP.OP_INS_ChangedAt,
    pOP.OP_INS_Operations_RowsInserted,
    pOP.OP_UPD_OP_ID,
    pOP.OP_UPD_ChangedAt,
    pOP.OP_UPD_Operations_RowsUpdated,
    pOP.OP_DEL_OP_ID,
    pOP.OP_DEL_ChangedAt,
    pOP.OP_DEL_Operations_RowsDeleted,
    pOP.OP_MRG_OP_ID,
    pOP.OP_MRG_ChangedAt,
    pOP.OP_MRG_Operations_RowsMerged
FROM
    metadata.OP_UPD_Operations_RowsUpdated hUPD,
    TABLE(metadata.pOP_Operations(hUPD.OP_UPD_ChangedAt::timestamp_tz)) pOP
WHERE
    (selection IS NULL OR selection LIKE '%UPD%')
AND
    hUPD.OP_UPD_ChangedAt BETWEEN intervalStart AND intervalEnd
AND
    pOP.OP_ID = hUPD.OP_UPD_OP_ID
UNION
SELECT DISTINCT
    hDEL.OP_DEL_ChangedAt::timestamp_tz AS inspectedTimepoint,
    'DEL' AS mnemonic,
    pOP.OP_ID,
    pOP.OP_INS_OP_ID,
    pOP.OP_INS_ChangedAt,
    pOP.OP_INS_Operations_RowsInserted,
    pOP.OP_UPD_OP_ID,
    pOP.OP_UPD_ChangedAt,
    pOP.OP_UPD_Operations_RowsUpdated,
    pOP.OP_DEL_OP_ID,
    pOP.OP_DEL_ChangedAt,
    pOP.OP_DEL_Operations_RowsDeleted,
    pOP.OP_MRG_OP_ID,
    pOP.OP_MRG_ChangedAt,
    pOP.OP_MRG_Operations_RowsMerged
FROM
    metadata.OP_DEL_Operations_RowsDeleted hDEL,
    TABLE(metadata.pOP_Operations(hDEL.OP_DEL_ChangedAt::timestamp_tz)) pOP
WHERE
    (selection IS NULL OR selection LIKE '%DEL%')
AND
    hDEL.OP_DEL_ChangedAt BETWEEN intervalStart AND intervalEnd
AND
    pOP.OP_ID = hDEL.OP_DEL_OP_ID
UNION
SELECT DISTINCT
    hMRG.OP_MRG_ChangedAt::timestamp_tz AS inspectedTimepoint,
    'MRG' AS mnemonic,
    pOP.OP_ID,
    pOP.OP_INS_OP_ID,
    pOP.OP_INS_ChangedAt,
    pOP.OP_INS_Operations_RowsInserted,
    pOP.OP_UPD_OP_ID,
    pOP.OP_UPD_ChangedAt,
    pOP.OP_UPD_Operations_RowsUpdated,
    pOP.OP_DEL_OP_ID,
    pOP.OP_DEL_ChangedAt,
    pOP.OP_DEL_Operations_RowsDeleted,
    pOP.OP_MRG_OP_ID,
    pOP.OP_MRG_ChangedAt,
    pOP.OP_MRG_Operations_RowsMerged
FROM
    metadata.OP_MRG_Operations_RowsMerged hMRG,
    TABLE(metadata.pOP_Operations(hMRG.OP_MRG_ChangedAt::timestamp_tz)) pOP
WHERE
    (selection IS NULL OR selection LIKE '%MRG%')
AND
    hMRG.OP_MRG_ChangedAt BETWEEN intervalStart AND intervalEnd
AND
    pOP.OP_ID = hMRG.OP_MRG_OP_ID
$$
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
CREATE OR REPLACE VIEW metadata.lTR_operates_CO_source_CO_target_OP_with AS
SELECT
    tie.TR_ID_operates,
    tie.CO_ID_source,
    tie.CO_ID_target,
    tie.OP_ID_with
FROM
    metadata.TR_operates_CO_source_CO_target_OP_with tie
;
-- Point-in-time perspective ------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata.pTR_operates_CO_source_CO_target_OP_with (
    changingTimepoint timestamp_tz
)
RETURNS TABLE (
    TR_ID_operates int,
    CO_ID_source int,
    CO_ID_target int,
    OP_ID_with int
)
AS
$$
SELECT
    tie.TR_ID_operates,
    tie.CO_ID_source,
    tie.CO_ID_target,
    tie.OP_ID_with
FROM
    metadata.TR_operates_CO_source_CO_target_OP_with tie
$$
;
-- Now perspective ----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata.nTR_operates_CO_source_CO_target_OP_with AS
SELECT
    *
FROM
    TABLE(metadata.pTR_operates_CO_source_CO_target_OP_with(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)::timestamp_tz))
;
-- Latest perspective -------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata.lTR_formed_CF_from AS
SELECT
    tie.TR_ID_formed,
    tie.CF_ID_from
FROM
    metadata.TR_formed_CF_from tie
;
-- Point-in-time perspective ------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata.pTR_formed_CF_from (
    changingTimepoint timestamp_tz
)
RETURNS TABLE (
    TR_ID_formed int,
    CF_ID_from int
)
AS
$$
SELECT
    tie.TR_ID_formed,
    tie.CF_ID_from
FROM
    metadata.TR_formed_CF_from tie
$$
;
-- Now perspective ----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata.nTR_formed_CF_from AS
SELECT
    *
FROM
    TABLE(metadata.pTR_formed_CF_from(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)::timestamp_tz))
;
-- Latest perspective -------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata.lCF_uses_TP_template AS
SELECT
    tie.CF_ID_uses,
    tie.TP_ID_template
FROM
    metadata.CF_uses_TP_template tie
;
-- Point-in-time perspective ------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION metadata.pCF_uses_TP_template (
    changingTimepoint timestamp_tz
)
RETURNS TABLE (
    CF_ID_uses int,
    TP_ID_template int
)
AS
$$
SELECT
    tie.CF_ID_uses,
    tie.TP_ID_template
FROM
    metadata.CF_uses_TP_template tie
$$
;
-- Now perspective ----------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW metadata.nCF_uses_TP_template AS
SELECT
    *
FROM
    TABLE(metadata.pCF_uses_TP_template(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP)::timestamp_tz))
;
-- DESCRIPTIONS -------------------------------------------------------------------------------------------------------