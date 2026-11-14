<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- a count pattern that is no pattern -->
<xsl:template match="/"><r><xsl:number count="1+"/></r></xsl:template>
</xsl:stylesheet>
