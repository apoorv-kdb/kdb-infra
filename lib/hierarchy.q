/ hierarchy.q
/ Flatten hierarchical data from wide level columns to parent-child format
/ Stateless: table in, table out

/ ============================================================================
/ FLATTEN
/ ============================================================================

/ Build ID by concatenating level values with | separator
.hierarchy.buildId:{[data; idCols]
  {`$"|" sv string x}each flip data idCols
 }

/ Flatten wide hierarchy into parent-child format
/ Args:
/   data: table with date, level columns, and metric columns
/   levelCols: symbol list of hierarchy columns in order
/   metricCols: symbol list of metric columns to aggregate
/   dateCols: symbol list of key columns beyond hierarchy (default: enlist `date)
/ Returns: table with (dateCols, `h_name`h_id`h_pid`h_depth, metricCols)
.hierarchy.flatten:{[data; levelCols; metricCols; dateCols]
  if[(::) ~ dateCols; dateCols:enlist `date];
  nLevels:count levelCols;

  result:raze {[data; levelCols; metricCols; dateCols; depth]
    lvl:levelCols depth;
    idCols:(depth + 1)#levelCols;
    ids:.hierarchy.buildId[data; idCols];
    pids:$[depth = 0;
      count[data]#enlist `;
      .hierarchy.buildId[data; depth#levelCols]];
    names:data lvl;

    / Aggregate metrics at this level
    groupCols:dateCols , idCols;
    agg:?[data; (); {x!x} groupCols; {x!((sum;) each x)} metricCols];

    / Build id/pid for aggregated rows
    aggIds:.hierarchy.buildId[agg; idCols];
    aggPids:$[depth = 0;
      count[agg]#enlist `;
      .hierarchy.buildId[agg; depth#levelCols]];
    aggNames:agg lvl;

    / Construct output
    base:dateCols#agg;
    base:base,'([] h_name:aggNames; h_id:aggIds; h_pid:aggPids; h_depth:count[agg]#depth);
    base,'metricCols#agg
  }[data; levelCols; metricCols; dateCols] each til nLevels;

  result
 }

/ ============================================================================
/ NAVIGATION
/ ============================================================================

.hierarchy.children:{[data; parentId]
  select from data where h_pid = parentId
 }

.hierarchy.descendants:{[data; parentId]
  direct:.hierarchy.children[data; parentId];
  if[0 = count direct; :direct];
  direct , raze {[data; row] .hierarchy.descendants[data; row`h_id]} [data] each 0!direct
 }

.hierarchy.path:{[data; id]
  node:select from data where h_id = id;
  if[0 = count node; :node];
  pid:first node`h_pid;
  if[` ~ pid; :node];
  .hierarchy.path[data; pid] , node
 }

.hierarchy.roots:{[data] select from data where h_pid = `}

.hierarchy.leaves:{[data]
  parentIds:distinct data`h_pid;
  select from data where not h_id in parentIds
 }

.hierarchy.atDepth:{[data; depth] select from data where h_depth = depth}

/ ============================================================================
/ CUSTOM GROUPING
/ ============================================================================

.hierarchy.addCustomGroup:{[data; mapping]
  / mapping: table with h_id and h_custom columns
  data lj `h_id xkey mapping
 }

.hierarchy.aggregateByCustom:{[data; metricCols; dateCols]
  if[(::) ~ dateCols; dateCols:enlist `date];
  groupCols:dateCols , enlist `h_custom;
  ?[data; (); {x!x} groupCols; {x!((sum;) each x)} metricCols]
 }
