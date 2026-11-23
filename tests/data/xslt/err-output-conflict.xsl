<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- two xsl:output of one precedence with different values: XTSE1560 -->
<xsl:output indent="no"/>
<xsl:output indent="yes"/>
<xsl:template match="/"><r/></xsl:template>
</xsl:stylesheet>
