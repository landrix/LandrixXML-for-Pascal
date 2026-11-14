<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- format-dateTime(), format-date(), format-time() -->
<xsl:output method="text"/>
<xsl:template match="/">
<xsl:variable name="d" select="xs:dateTime('2026-01-04T07:05:03.270+01:00')"/>
<xsl:variable name="u" select="xs:dateTime('2026-11-14T23:59:09Z')"/>
<xsl:variable name="n" select="xs:dateTime('2026-03-02T00:00:00')"/>
<xsl:for-each select="'[D].[M].[Y] [H]:[m]:[s]', '[D01].[M01].[Y0001]', '[f]', '[f001]', '[f1]', '[Z]', '[z]', '[F]', '[FNn]', '[FN,3-3]', '[F1]', '[P]', '[h]', '[MNn]', '[Mn,3-3]', '[MN,*-3]', '[Y,2]', '[Y,2-2]', '[YI]', '[Di]', '[d]', '[W]', '[C]', '[E]', '[[x]] [Y]', '[ D ]', '[Y01]', '[Y001]', '[M,2]', '[H01]', '[m1]', '[s1]', '[Z0]', '[Z00:00]', '[Z0000]', '[Z01]', '[MNn,6-6]', '[FNn,2-3]'">
<xsl:value-of select="concat(., ' = ', format-dateTime($d, .), ' | ', format-dateTime($u, .), ' | ', format-dateTime($n, .))"/><xsl:text>&#10;</xsl:text>
</xsl:for-each>
<xsl:value-of select="format-date(xs:date('2026-11-14'), '[D].[M].[Y]')"/><xsl:text>&#10;</xsl:text>
<xsl:value-of select="format-date(xs:date('2026-12-28'), '[W] [F1]')"/><xsl:text>&#10;</xsl:text>
<xsl:value-of select="format-date(xs:date('2027-01-01'), '[W] [F1]')"/><xsl:text>&#10;</xsl:text>
<xsl:value-of select="format-time(xs:time('13:04:00'), '[h]:[m] [P]')"/><xsl:text>&#10;</xsl:text>
<xsl:value-of select="format-dateTime($d, '[D] [MNn] [Y]', 'de', (), ())"/><xsl:text>&#10;</xsl:text>
<xsl:value-of select="format-dateTime($d, '[D]. [MNn] [Y]', 'en', (), ())"/><xsl:text>&#10;</xsl:text>
<xsl:value-of select="format-dateTime((), '[D]')"/><xsl:text>|&#10;</xsl:text>
<xsl:value-of select="format-date(xs:date('-0044-03-15'), '[Y] [E]')"/><xsl:text>&#10;</xsl:text>
<xsl:value-of select="format-dateTime(/format-date/@t, '[Y]-[M01]')"/><xsl:text>&#10;</xsl:text>
</xsl:template>
</xsl:stylesheet>
