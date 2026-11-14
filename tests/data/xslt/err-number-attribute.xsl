<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- an attribute xsl:number does not have -->
<xsl:template match="/"><r><xsl:number value="1" foo="1"/></r></xsl:template>
</xsl:stylesheet>
