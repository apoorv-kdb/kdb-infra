/ rolling.q
/ Windowed statistics over time series data
/ Stateless: table in, table out

/ ============================================================================
/ CORE WINDOW FUNCTIONS
/ ============================================================================

.rolling.movAvg:{[vals; window] mavg[window; vals]}
.rolling.movSum:{[vals; window] msum[window; vals]}
.rolling.movStd:{[vals; window] mdev[window; vals]}
.rolling.movMin:{[vals; window] mmin[window; vals]}
.rolling.movMax:{[vals; window] mmax[window; vals]}
.rolling.movMedian:{[vals; window] mmed[window; vals]}

/ ============================================================================
/ TABLE OPERATIONS
/ ============================================================================

/ Add a single rolling statistic to a table
/ Args:
/   data: table (must be sorted by date)
/   col: symbol - column to compute over
/   window: int - window size in rows
/   fn: symbol - one of `avg`sum`std`min`max`median
/   outCol: symbol - output column name
/ Returns: table with new column added
.rolling.addRolling:{[data; col; window; fn; outCol]
  vals:data col;
  computed:$[fn;
    `avg;    .rolling.movAvg[vals; window];
    `sum;    .rolling.movSum[vals; window];
    `std;    .rolling.movStd[vals; window];
    `min;    .rolling.movMin[vals; window];
    `max;    .rolling.movMax[vals; window];
    `median; .rolling.movMedian[vals; window];
    '"Unknown rolling function: ",string fn];
  ![data; (); 0b; (enlist outCol)!(enlist computed)]
 }

/ Add multiple rolling statistics at once
/ Args:
/   data: table
/   specs: list of dicts with `col`window`fn`outCol
/ Returns: table with all new columns
.rolling.addMultiple:{[data; specs]
  {[data; spec]
    .rolling.addRolling[data; spec`col; spec`window; spec`fn; spec`outCol]
  }/[data; specs]
 }

/ Grouped rolling (e.g. per business unit)
/ Args:
/   data: table
/   groupCol: symbol - grouping column
/   col, window, fn, outCol: same as addRolling
/ Returns: table with rolling stat computed within each group
.rolling.addRollingBy:{[data; groupCol; col; window; fn; outCol]
  groups:distinct data groupCol;
  result:raze {[data; groupCol; col; window; fn; outCol; grp]
    subset:`date xasc select from data where (groupCol#data)[groupCol] = grp;
    .rolling.addRolling[subset; col; window; fn; outCol]
  }[data; groupCol; col; window; fn; outCol] each groups;
  `date xasc result
 }

/ ============================================================================
/ CONVENIENCE
/ ============================================================================

/ Generate standard specs (avg, std, min, max) for a column + window
.rolling.standardSpecs:{[col; window]
  suffixes:`avg`std`min`max;
  fns:`avg`std`min`max;
  {[col; window; suffix; fn]
    `col`window`fn`outCol!(col; window; fn; `$string[col],"_",string[window],"d_",string suffix)
  }[col; window] ./: flip (suffixes; fns)
 }
