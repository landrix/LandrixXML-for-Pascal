<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- an empty calendar -->
<xsl:template match="/"><r><xsl:value-of select="format-date(xs:date('2020-01-02'), '[Y]', (), '', ())"/></r></xsl:template>
</xsl:stylesheet>
