requests
| where timestamp between (datetime(2026-07-30 00:10:19) .. datetime(2026-07-30 00:40:30))
| summarize dcount(cloud_RoleInstance) by bin(timestamp, 1m)
| render timechart
