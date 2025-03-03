2.1.0
=====

FEATURES
--------
 - Add the ability to choose between a materialized view or normal view for some metrics that had previously been materialiezd view only.
    - `ccp_stat_database` & `ccp_stat_user_tables` are now views by default since their values can be different on the replica vs the primary. This was causing some confusion for users so the default as a view should correct this. 
        - For `ccp_stat_user_tables`, it is possible to have these stats pull from a materialzed view instead if desired in case of performance issues on PostgreSQL instances with very large numbers of tables. 
    - `ccp_stat_database` shouldn't have performance issues and didn't really need a materialized view. It will now only have a normal view available in pgMonitor.
    - `ccp_database_size` and `ccp_table_size` still default to being backed by materialized views since these values should not vary on replicas. But users now have the choice to have these be backed by a normal view. A normal view is not recommended if the database is expected to grow very large in size.
    - All remaining materialized view backed metrics only have the option for being materialized view backed. Please see the updated table in the documentation to see which metrics are backed by views, materialized views, or have the choice of either. 
 - New configuration table for materialized views: `metrics_matviews`
    - All materialized views that were in `metric_views` have been moved to this new table
    - Configuration columns that were only relevant to materialized views have been removed from `metric_views`
    - The `materialized_view` boolean column in `metric_views` has been renamed to `matview_source`
        - This now defaults to false instead of true
        - This column is now used to allow the choice between the given view's data source being a materialized view or a direct query
 - Add additional metrics for monitoring replication slot status. For PG16+ monitor for conflicts. For PG17+, monitor synced and failover status.
 - Ensure special functions are named consistently. Version function names end in `_func`. Matview choice function names end in `_choice`.
 - Moved activating the `ccp_pg_stat_statements_reset` automated call from being in the metric_views configuration table to the metric_tables configuration table. Interval control columns no longer exist in metric_views so this made the most sense. If this reset had been active before, it should remain active after the migration.
    
BUGFIXES
--------
 - Rename the column in the view `ccp_table_size` from `size_bytes` to just `bytes`. Allows for the underlying metric in the pgMonitor project to be more consistent with the metric name (`ccp_table_size_bytes` vs `ccp_table_size_size_bytes`). Also makes it consistent with other size measurement column names.
 - Allow pg_stat_statements to be installed in any user defined schema if those metrics are being used.


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
