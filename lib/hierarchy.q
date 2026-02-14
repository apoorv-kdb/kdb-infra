/ hierarchy.q
/ Flatten hierarchical data from wide level columns to parent-child format
/
/ Input shape:  date, h_level1, h_level2, h_level3, ..., metrics
/ Output shape: date, h_name, h_id, h_pid, h_depth, metrics
/
/ Stateless: table in, table out

\d .hierarchy

/ ============================================================================
/ FLATTEN
/ ============================================================================

/ Flatten a wide hierarchy into parent-child format
/ Each level becomes its own row with an id and parent id
/ Args:
/   data: table with date, level columns, and metric columns
/   levelCols: symbol list of hierarchy columns in order (e.g. `h_level1`h_level2`h_level3)
/   metricCols: symbol list of metric columns to carry through
/   dateCols: symbol list of key columns beyond the hierarchy (default: enlist `date)
/ Returns: table with (dateCols, `h_name`h_id`h_pid`h_depth, metricCols)
flatten:{[data; levelCols; metricCols; dateCols]
  if[(::) ~ dateCols; dateCols:enlist `date];
  nLevels:count levelCols;

  / Build rows for each level
  result:raze {[data; levelCols; metricCols; dateCols; depth]
    lvl:levelCols depth;

    / Build the id: concatenation of all levels up to and including this one
    idCols:(depth + 1)#levelCols;
    ids:buildId[data; idCols];

    / Build the parent id: concatenation of levels up to parent
    pids:$[depth = 0;
      count[data]#enlist `;
      buildId[data; depth#levelCols]];

    / The name at this level
    names:data lvl;

    / Aggregate metrics at this level
    groupCols:dateCols , idCols;
    agg:?[data; (); {x!x} groupCols; {x!((sum;) each x)} metricCols];

    / Rebuild ids and pids from the aggregated table
    aggIds:buildId[agg; idCols];
    aggPids:$[depth = 0;
      count[agg]#enlist `;
      buildId[agg; depth#levelCols]];
    aggNames:agg lvl;

    / Build output
    base:dateCols#agg;
    base:base,'([] h_name:aggNames; h_id:aggIds; h_pid:aggPids; h_depth:count[agg]#depth);
    base,'metricCols#agg
  }[data; levelCols; metricCols; dateCols] each til nLevels;

  `h_depth xasc result
 }

/ ============================================================================
/ ID CONSTRUCTION
/ ============================================================================

/ Build a composite id from multiple columns by joining with "|"
/ Args: data (table), cols (symbol list)
/ Returns: symbol list
buildId:{[data; cols]
  `$"|" sv' string each flip cols#data
 }

/ ============================================================================
/ HIERARCHY UTILITIES
/ ============================================================================

/ Get all children of a given id
children:{[data; parentId]
  select from data where h_pid = parentId
 }

/ Get all descendants of a given id (recursive)
descendants:{[data; parentId]
  direct:select from data where h_pid = parentId;
  if[0 = count direct; :direct];
  direct,raze {[data] .hierarchy.descendants[data; x]} each exec h_id from direct
 }

/ Note: descendants passes `data` that should be the full table
/ Correct recursive usage:
descendants:{[data; parentId]
  direct:select from data where h_pid = parentId;
  if[0 = count direct; :direct];
  childIds:exec h_id from direct;
  direct,raze .hierarchy.descendants[data;] each childIds
 }

/ Get the path from root to a given id
path:{[data; id]
  row:select from data where h_id = id;
  if[0 = count row; :row];
  pid:first exec h_pid from row;
  if[` ~ pid; :row];
  .hierarchy.path[data; pid],row
 }

/ Get all nodes at a given depth
atDepth:{[data; depth]
  select from data where h_depth = depth
 }

/ Get root nodes
roots:{[data]
  select from data where h_pid = `
 }

/ Get leaf nodes (nodes that are not parents of anything)
leaves:{[data]
  allPids:distinct exec h_pid from data;
  select from data where not h_id in allPids
 }

/ ============================================================================
/ CUSTOM HIERARCHY
/ ============================================================================

/ Remap hierarchy using a custom mapping table
/ Args:
/   data: flattened hierarchy table (output of flatten)
/   mapping: table with columns `h_id`h_custom - maps each id to a custom grouping
/ Returns: table with h_custom column added
addCustomGroup:{[data; mapping]
  data lj `h_id xkey select h_id, h_custom from mapping
 }

/ Aggregate a flattened hierarchy to a custom grouping level
/ Args:
/   data: flattened hierarchy table with h_custom column
/   metricCols: symbol list of metric columns to aggregate
/   dateCols: symbol list of date/key columns (default: enlist `date)
/ Returns: aggregated table grouped by dateCols and h_custom
aggregateByCustom:{[data; metricCols; dateCols]
  if[(::) ~ dateCols; dateCols:enlist `date];
  groupCols:dateCols , enlist `h_custom;
  ?[data; (); {x!x} groupCols; {x!((sum;) each x)} metricCols]
 }

\d .
