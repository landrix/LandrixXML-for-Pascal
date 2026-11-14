<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- current-group() outside a group -->
<xsl:template match="/"><o c="{count(current-group())}"/></xsl:template>
</xsl:stylesheet>
