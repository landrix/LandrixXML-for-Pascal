<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- day and month names in a width (Saxon's short forms); fractional
     seconds with tokens and widths -->
<xsl:output method="text"/>
<xsl:template match="/">
<xsl:for-each select="0 to 6">
  <xsl:variable name="d" select="xs:date('2026-11-16') + xs:dayTimeDuration(concat('P', ., 'D'))"/>
  <xsl:value-of select="for $w in 1 to 8 return format-date($d, concat('[FNn,', $w, '-', $w, ']'))" separator="|"/>
  <xsl:text>&#10;</xsl:text>
</xsl:for-each>
<xsl:for-each select="1 to 12">
  <xsl:variable name="d" select="xs:date('2026-01-01') + xs:yearMonthDuration(concat('P', . - 1, 'M'))"/>
  <xsl:value-of select="for $w in 1 to 5 return format-date($d, concat('[MN,', $w, '-', $w, ']'))" separator="|"/>
  <xsl:text>&#10;</xsl:text>
</xsl:for-each>
<xsl:variable name="t" select="xs:dateTime('2024-03-05T14:07:09.123456789+05:30')"/>
<xsl:value-of select="for $p in ('[f001]', '[f01]', '[f00001]', '[f001,1-2]', '[f1]', '[f,3-3]', '[f01,4-4]',
  '[f01,*-5]', '[f001,5-5]', '[f,2-*]', '[f0]') return format-dateTime($t, $p)" separator="|"/>
<xsl:text>&#10;</xsl:text>
<xsl:value-of select="format-time(xs:time('03:04:05.0001'), '[f01]|[f001]')"/>
<xsl:text>&#10;</xsl:text>
<xsl:value-of select="format-date(xs:date('2026-01-01'), '[Y]', (), 'AD', ())"/>
</xsl:template>
</xsl:stylesheet>
