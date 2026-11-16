<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- format-date: words, ordinals, letters, year cut to a width -->
<xsl:template match="/"><r>
<xsl:for-each select="'[D1o]', '[D01o]', '[DW]', '[Dw]', '[DWw]', '[DWo]', '[Dwo]', '[DWwo]', '[Y1o]', '[Yw]', '[YWwo]',
  '[Y01o]', '[Y1,*-2]', '[Y,2-2]', '[Y001]', '[Y1,*-3]', '[Y01o,*-3]', '[Yw,2-2]', '[Ywo,*-1]', '[Ya]', '[YA,*-2]',
  '[Da]', '[Dao]', '[DIo]', '[FWo]', '[MWo]', '[MNno]', '[H1o]', '[Hwo]', '[Ha]', '[mwo]', '[dwo]', '[Wwo]', '[D1c]',
  '[Dw,3-3]'">
<d p="{.}"><xsl:value-of select="format-dateTime(xs:dateTime('2013-09-23T00:05:01'), .)"/></d>
</xsl:for-each>
<y><xsl:value-of select="format-date(xs:date('1234567890-01-01'), '[Y1,*-9]'), format-date(xs:date('1234567890-01-01'), '[Y1,*-8]')"/></y>
<xsl:for-each select="1 to 31">
<o><xsl:value-of select="format-date(xs:date('2001-01-01') + xs:dayTimeDuration('P1D') * (. - 1), '[D1o] [Dwo]')"/></o>
</xsl:for-each>
</r></xsl:template>
</xsl:stylesheet>
