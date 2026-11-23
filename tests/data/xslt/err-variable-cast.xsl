<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- the conversion of xs:untypedAtomic fails: XTTE0570, not FORG0001 -->
<xsl:template match="/"><r><xsl:variable name="v" as="xs:integer" select="xs:untypedAtomic('a')"/><xsl:value-of select="$v"/></r></xsl:template>
</xsl:stylesheet>
