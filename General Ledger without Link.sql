WITH GL_Summary AS (
  SELECT
    `posting_date` AS `Posting Date`,
    `voucher_type` AS `Voucher Type`,
    `voucher_no` AS `Voucher No`,
    `account` AS `Account`,  -- Hidden but kept for reference
    `party` AS `Party`,
    `against` AS `Against`,
    `remarks` AS `Remarks`,
    `debit` AS `Total Debit`,
    `credit` AS `Total Credit`
  FROM
    `tabGL Entry`
  WHERE
    `posting_date` <= %(end_date)s
    AND `account` LIKE COALESCE(%(account)s, '%%')
    AND `company` = %(company)s
    AND `is_cancelled` = 0
    AND `party_type` = %(party_type)s
    AND `party` LIKE COALESCE(%(party)s, '%%')
),
Opening_Balance AS (
  SELECT
    `account`,
    `party`,
    SUM(`debit` - `credit`) AS `Opening Balance`
  FROM
    `tabGL Entry`
  WHERE
    `posting_date` < %(start_date)s
    AND `account` LIKE COALESCE(%(account)s, '%%')
    AND `company` = %(company)s
    AND `is_cancelled` = 0
    AND `party_type` = %(party_type)s
    AND `party` LIKE COALESCE(%(party)s, '%%')
  GROUP BY
    `account`, `party`
),
Filtered_GL_Summary AS (
  SELECT
    *
  FROM
    GL_Summary
  WHERE
    `Posting Date` BETWEEN %(start_date)s AND %(end_date)s
),
Invoice_Items AS (
  SELECT
    `parent` AS `Voucher No`,
    CONCAT(
      `item_name`, ' - ',
      FORMAT(`qty`, 2), ' x ', 
      FORMAT(`rate`, 2), ' = ', 
      FORMAT(`qty` * `rate`, 2)
    ) AS `Descriptions`,
    ROW_NUMBER() OVER (PARTITION BY `parent` ORDER BY `item_name`) AS `Item_Row_Number`
  FROM
    `tabSales Invoice Item`
  UNION ALL
  SELECT
    `parent` AS `Voucher No`,
    CONCAT(
      `item_name`, ' - ',
      FORMAT(`qty`, 2), ' x ', 
      FORMAT(`rate`, 2), ' = ', 
      FORMAT(`qty` * `rate`, 2)
    ) AS `Descriptions`,
    ROW_NUMBER() OVER (PARTITION BY `parent` ORDER BY `item_name`) AS `Item_Row_Number`
  FROM
    `tabPurchase Invoice Item`
),
All_Transactions AS (
  SELECT
    fgs.`Posting Date`,
    fgs.`Voucher Type`,
    fgs.`Voucher No`,
    fgs.`Account`,
    fgs.`Party`,
    fgs.`Against`,
    COALESCE(ii.`Descriptions`, fgs.`Remarks`) AS `Descriptions`,
    CASE 
      WHEN ii.`Voucher No` IS NOT NULL AND ii.`Item_Row_Number` = 1 THEN fgs.`Total Debit`
      WHEN ii.`Voucher No` IS NULL THEN fgs.`Total Debit`
      ELSE 0 
    END AS `Debit`,
    CASE 
      WHEN ii.`Voucher No` IS NOT NULL AND ii.`Item_Row_Number` = 1 THEN fgs.`Total Credit`
      WHEN ii.`Voucher No` IS NULL THEN fgs.`Total Credit`
      ELSE 0 
    END AS `Credit`
  FROM
    Filtered_GL_Summary fgs
  LEFT JOIN Invoice_Items ii ON fgs.`Voucher No` = ii.`Voucher No`
),
Final_Balance AS (
  SELECT
    at.`Posting Date`,
    at.`Voucher No`,
    at.`Descriptions`,
    at.`Debit`,  -- Keep float format
    at.`Credit`, -- Keep float format
    SUM(at.`Debit` - at.`Credit`) OVER (
      ORDER BY at.`Posting Date`, at.`Voucher No`
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) + COALESCE(ob.`Opening Balance`, 0) AS `Running Balance`
  FROM
    All_Transactions at
  LEFT JOIN Opening_Balance ob ON at.`Account` = ob.`account` AND at.`Party` = ob.`party`
)
SELECT
  fb.`Posting Date`,
  fb.`Voucher No`,
  fb.`Descriptions`,
  FORMAT(fb.`Debit`, 2) AS `Debit`,       -- Add commas for display
  FORMAT(fb.`Credit`, 2) AS `Credit`,     -- Add commas for display
  FORMAT(fb.`Running Balance`, 2) AS `Balance`
FROM Final_Balance fb
ORDER BY
  fb.`Posting Date` ASC,
  fb.`Voucher No` ASC;
