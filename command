
SELECT VALUE SUM(c.amount) FROM c
WHERE c.ledgerId = 'a0c1b2d3-e4f5-6789-abcd-ef0123456789'
  AND c.createdAt <= '2026-07-23T23:59:59.0000000Z'
[
    50180.04
]


SELECT VALUE SUM(c.amount) FROM c WHERE c.ledgerId = 'a0c1b2d3-e4f5-6789-abcd-ef0123456789'
[
    49824.24
]
