/ dates.q
/ Date utilities for navigating partition dates
/ Stateless: values in, values out

/ Get the most recent date on or before asOfDate from a sorted date list
.dates.asOf:{[dates; asOfDate]
  valid:dates where dates <= asOfDate;
  $[0 = count valid; 0Nd; last valid]
 }

/ Get the previous date before a given date
.dates.prev:{[dates; dt]
  prior:dates where dates < dt;
  $[0 = count prior; 0Nd; last prior]
 }

/ Get the next date after a given date
.dates.next:{[dates; dt]
  after:dates where dates > dt;
  $[0 = count after; 0Nd; first after]
 }

/ Get date N business days ago (from a date list)
.dates.nAgo:{[dates; dt; n]
  idx:dates ? dt;
  if[null idx; :0Nd];
  targetIdx:idx - n;
  $[targetIdx < 0; 0Nd; dates targetIdx]
 }

/ Get last date of each month from a date list
.dates.monthEnds:{[dates]
  months:`month$dates;
  last each group months
 }

/ Get first date of each month
.dates.monthStarts:{[dates]
  months:`month$dates;
  first each group months
 }

/ Business day count between two dates in a date list
.dates.bdCount:{[dates; startDt; endDt]
  count dates where dates within (startDt; endDt)
 }

/ Generate date range
.dates.range:{[startDt; endDt]
  startDt + til 1 + endDt - startDt
 }
