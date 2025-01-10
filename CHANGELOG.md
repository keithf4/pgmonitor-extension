2.1.0
=====

FEATURES
--------
 - Add additional metrics for monitoring replication slot status. For PG16+, monitor slot type and for conflicts. For PG17+, monitor synced and failover status.


BUGFIXES
--------
 - Rename the column in the view `ccp_table_size` from `size_bytes` to just `bytes`. Allows for the underlying metric in the pgMonitor project to be more consistent with the metric name (`ccp_table_size_bytes` vs `ccp_table_size_size_bytes`). Also makes it consistent with other size measurement column names.


2.0.0
=====

FEATURES
--------
 - Compatible with PostgreSQL 17

BREAKING CHANGES
----------------
 - PG17 restructured the pg_stat_bgwriter catalog information. This extension has been restructured around those changes:
    - Changed the `ccp_stat_bgwriter` metric from a materialized view to a standard view
    - Removed columns from `ccp_stat_bgwriter` that are no longer part of `pg_catalog.pg_stat_bgwriter`
    - New metrics views created: `ccp_stat_checkpointer` and `ccp_stat_io_bgwriter`. These align with where the columns from `pg_stat_bgwriter` were moved to.
    - For versions of PG older than 17, these new metrics still apply and simply pull that data from the original `pg_stat_bgwriter` catalog and present them in the new format.
    - All applications that made use of the old `ccp_stat_bgwriter` metric will need to be updated to use the new metrics.
    - Due to dropping old metrics and recreating new ones, permissions may need to be regranted to any monitoring roles that use these new views.


1.0.1
=====

BUGFIXES
--------
 - The first three number version of pgBackRest (2.52.1) was not being handled properly. Fix handling of version number so that it now returns a padded integer similar to PostgreSQL's server_version_num.
