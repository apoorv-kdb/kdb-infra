/ catalog.q
/ Per-app field catalog loaded from CSV at server startup
/ Drives HTTP query validation and /catalog/* endpoint responses

/ CSV columns: app, table, field, label, type, role, format, enabled
/   role:   categorical | value | temporal
/   type:   kdb+ type string: symbol | float | long | date | timestamp
/   format: currency | integer | percent | date | (empty)

/ Dependencies: none

.catalog.fields:flip `app`table`field`label`type`role`format`enabled!8#enlist`$()

/ Load a catalog CSV for the given app name
/ Filters to enabled=1 rows immediately
/ Call once at server startup: .catalog.load["config/catalog_sales.csv"; `sales]
.catalog.load:{[path; app]
  raw:("SSSSSSSB"; enlist ",") 0: hsym `$path;
  .catalog.fields:select from raw where enabled, app=`$string app;
  show "  Catalog: ",string[count .catalog.fields]," fields loaded for app '",string[app],"'";
 }

.catalog.reload:{[path; app] .catalog.load[path; app]}

/ ============================================================================
/ LOOKUPS
/ ============================================================================

.catalog.byRole:{[role]
  select from .catalog.fields where role=role
 }

/ Return metadata dict for one field, empty dict if not found
.catalog.meta:{[field]
  res:select from .catalog.fields where field=field;
  $[count res; first res; ()!()]
 }

.catalog.tableFor:{[field]
  m:.catalog.meta field;
  $[count m; m`table; `]
 }

.catalog.typeOf:{[field]
  m:.catalog.meta field;
  $[count m; m`type; `]
 }

/ ============================================================================
/ VALIDATION
/ ============================================================================

.catalog.isKnown:{[field]
  0 < count select from .catalog.fields where field=field
 }

.catalog.isRole:{[field; role]
  0 < count select from .catalog.fields where field=field, role=role
 }

/ Throws descriptive error if field unknown or wrong role
.catalog.require:{[field; role]
  if[not .catalog.isKnown field; '"Unknown field: ",string field];
  if[not .catalog.isRole[field; role];
    actual:exec first role from .catalog.fields where field=field;
    '"Field '",string[field],"' has role '",string[actual],"' not '",string[role],"'"];
 }

/ ============================================================================
/ JSON HELPERS
/ ============================================================================

/ Table to list-of-dicts for .j.j serialisation
.catalog.tableToJson:{[tbl]
  if[0 = count tbl; :()];
  cs:cols tbl;
  {cs!x cs} each tbl
 }

/ Sanitise nulls before .j.j: numeric nulls → 0, symbol nulls → ""
.catalog.sanitise:{[row]
  {$[null v:x;
    $[0h > abs type v; 0; ""];
    v]} each row
 }

.catalog.sanitiseTable:{[tbl]
  if[0 = count tbl; :tbl];
  .catalog.sanitise each tbl
 }
