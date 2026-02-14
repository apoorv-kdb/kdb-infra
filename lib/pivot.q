/ pivot.q
/ Reshape tables between long and wide formats
/ Long to wide (pivot) and wide to long (unpivot/melt)
/
/ Stateless: table in, table out

\d .pivot

/ ============================================================================
/ LONG TO WIDE (PIVOT)
/ ============================================================================

/ Pivot a long table to wide format
/ Args:
/   data: table in long format
/   rowCols: symbol list - columns that define rows (e.g. `date)
/   pivotCol: symbol - column whose distinct values become new columns
/   valueCol: symbol - column whose values fill the pivoted cells
/   aggFn: function - aggregation if multiple values per cell (e.g. sum, first, avg)
/ Returns: wide table with rowCols + one column per distinct pivotCol value
toWide:{[data; rowCols; pivotCol; valueCol; aggFn]
  / Get distinct pivot values
  pivotVals:asc distinct data pivotCol;

  / Build each pivoted column
  grouped:?[data; (); {x!x} rowCols , enlist pivotCol; (enlist `val)!(enlist (aggFn; valueCol))];

  / Start with distinct row keys
  result:?[data; (); 0b; {x!x} rowCols];
  result:distinct result;

  / Join each pivot value as a new column
  {[result; grouped; rowCols; pivotCol; pv]
    slice:select from grouped where (pivotCol#grouped)[pivotCol] = pv;
    newCol:`$string pv;
    renamed:![slice; (); 0b; (enlist newCol)!(enlist slice`val)];
    renamed:![renamed; (); 0b; enlist pivotCol];
    renamed:![renamed; (); 0b; enlist `val];
    result lj rowCols xkey renamed
  }[; grouped; rowCols; pivotCol]/[result; pivotVals]
 }

/ Pivot with sum aggregation (most common case)
/ Args:
/   data: table
/   rowCols: symbol list
/   pivotCol: symbol
/   valueCol: symbol
/ Returns: wide table
sumWide:{[data; rowCols; pivotCol; valueCol]
  toWide[data; rowCols; pivotCol; valueCol; sum]
 }

/ ============================================================================
/ WIDE TO LONG (UNPIVOT / MELT)
/ ============================================================================

/ Unpivot a wide table to long format
/ Args:
/   data: table in wide format
/   idCols: symbol list - columns to keep as-is (e.g. `date`business)
/   valueCols: symbol list - columns to melt into rows
/   nameCol: symbol - name for the new column holding the original column names
/   valueCol: symbol - name for the new column holding the values
/ Returns: long table with idCols + nameCol + valueCol
toLong:{[data; idCols; valueCols; nameCol; valueCol]
  raze {[data; idCols; nameCol; valueCol; vc]
    base:idCols#data;
    base:![base; (); 0b; (enlist nameCol)!(enlist count[data]#vc)];
    base:![base; (); 0b; (enlist valueCol)!(enlist data vc)];
    base
  }[data; idCols; nameCol; valueCol] each valueCols
 }

/ Auto-detect value columns (everything not in idCols)
/ Args:
/   data: table
/   idCols: symbol list
/   nameCol: symbol
/   valueCol: symbol
/ Returns: long table
melt:{[data; idCols; nameCol; valueCol]
  valueCols:(cols data) except idCols;
  toLong[data; idCols; valueCols; nameCol; valueCol]
 }

/ ============================================================================
/ CROSS-TAB
/ ============================================================================

/ Create a cross-tabulation (two-way pivot)
/ Args:
/   data: table
/   rowCol: symbol - column for rows
/   colCol: symbol - column for columns
/   valueCol: symbol - column to aggregate
/   aggFn: function - aggregation (sum, count, avg)
/ Returns: keyed table with rowCol as key, colCol values as columns
crossTab:{[data; rowCol; colCol; valueCol; aggFn]
  toWide[data; enlist rowCol; colCol; valueCol; aggFn]
 }

/ ============================================================================
/ UTILITIES
/ ============================================================================

/ Fill nulls in a pivoted table with a default value
/ Args: data (table), fillVal (value), targetCols (symbol list or (::) for all non-key)
/ Returns: table with nulls replaced
fillNulls:{[data; fillVal; targetCols]
  if[(::) ~ targetCols; targetCols:cols data];
  {[d; col; fv]
    vals:d col;
    filled:?[null vals; count[vals]#fv; vals];
    ![d; (); 0b; (enlist col)!(enlist filled)]
  }[; ; fillVal]/[data; targetCols]
 }

/ Fill nulls with zero (common case for pivoted numeric data)
fillZero:{[data; targetCols]
  fillNulls[data; 0f; targetCols]
 }

\d .
