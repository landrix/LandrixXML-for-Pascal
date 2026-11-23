<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:m="urn:modes" exclude-result-prefixes="m">
<!-- declarations Saxon HE takes as equal: use-accumulators #all and none
     (no accumulator), streamable yes and no (no streaming), true and yes;
     the white space of a URI in Q{}; typed="strict" without a schema -->
<xsl:mode name="m:a" use-accumulators="#all" streamable="yes" typed="true"/>
<xsl:mode name="m:a" use-accumulators="" streamable="no" typed="yes"/>
<xsl:mode name="Q{  urn:modes  }b" on-no-match="deep-copy"/>
<xsl:mode name="m:s" typed="strict"/>
<xsl:template match="/"><r><xsl:apply-templates select="doc" mode="m:b"/></r></xsl:template>
</xsl:stylesheet>
