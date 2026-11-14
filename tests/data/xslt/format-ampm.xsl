<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- am/pm names; ISO weeks before year 1 -->
<xsl:output method="text"/>
<xsl:template match="/">
<xsl:value-of select="format-time(xs:time('12:00:00'), '[PN]'), format-time(xs:time('12:00:00'), '[PNn]'),
  format-time(xs:time('01:00:00'), '[Pn]'), format-time(xs:time('01:00:00'), '[P]'),
  format-date(xs:date('-0001-01-01'), '[W]'), format-date(xs:date('-0005-12-31'), '[W] [F1]')" separator="|"/>
</xsl:template>
</xsl:stylesheet>
