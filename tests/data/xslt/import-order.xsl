<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- an import in an included module counts at the position of the
     xsl:include: the later import (b) has the higher precedence -->
<xsl:include href="_inc.xsl"/>
<xsl:import href="_ib.xsl"/>
<xsl:template match="/"><o><xsl:value-of select="$v"/></o></xsl:template>
</xsl:stylesheet>
