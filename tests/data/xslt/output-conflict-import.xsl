<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- a conflict in an imported module is no error when a higher precedence sets the property; true and yes are equal -->
<xsl:import href="_output-conflict.xsl"/>
<xsl:output indent="no"/>
<xsl:output omit-xml-declaration="yes"/>
<xsl:output omit-xml-declaration="true"/>
<xsl:template match="/"><r><a/></r></xsl:template>
</xsl:stylesheet>
