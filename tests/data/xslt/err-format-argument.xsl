<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- a picture that is no string -->
<xsl:template match="/"><r><xsl:value-of select="format-date(xs:date('2026-01-01'), 42)"/></r></xsl:template>
</xsl:stylesheet>
