/ pivot.q
/ Pivot and unpivot operations for reshaping tables
/ Stateless: table in, table out

/ Pivot long to wide
/ Args:
/   data: table
/   rowCols: symbol list - columns that stay as rows
/   pivotCol: symbol - column whose values become new column headers
/   valueCol: symbol - column whose values fill the pivoted cells
/   aggFn: function - aggregation (e.g. sum, first, count)
/ Returns: wide table
.pivot.wide:{[data; rowCols; pivotCol; valueCol; aggFn]
  pivotVals:asc distinct data pivotCol;
  base:?[data; (); {x!x} rowCols; ()!()];

  {[data; base; rowCols; pivotCol; valueCol; aggFn; pv]
    subset:?[data; enlist (=; pivotCol; pv); 0b; ()];
    agged:?[subset; (); {x!x} rowCols; (enlist `$string pv)!(enlist (aggFn; valueCol))];
    base lj rowCols xkey agged
  }[data; ; rowCols; pivotCol; valueCol; aggFn]/[base; pivotVals]
 }

/ Unpivot wide to long
/ Args:
/   data: table
/   keyCols: symbol list - columns to keep
/   valueCols: symbol list - columns to melt into rows
/   nameCol: symbol - name for the new category column
/   valueCol: symbol - name for the new value column
/ Returns: long table
.pivot.long:{[data; keyCols; valueCols; nameCol; valueCol]
  raze {[data; keyCols; nameCol; valueCol; vc]
    base:keyCols#data;
    base:base,'([] x:data vc);
    base:![base; (); 0b; (enlist nameCol)!(enlist count[data]#vc)];
    `x xcol base
  }[data; keyCols; nameCol; valueCol] each valueCols
 }
