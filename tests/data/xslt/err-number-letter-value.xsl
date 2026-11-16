<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- letter-value neither alphabetic nor traditional -->
<xsl:template match="/"><r><xsl:number value="2" format="i" letter-value="roman"/></r></xsl:template>
</xsl:stylesheet>
