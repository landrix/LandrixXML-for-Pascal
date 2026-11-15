<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- the named format of xsl:result-document is declared after the
     template that uses it, as an EQName -->
<xsl:template match="/"><xsl:result-document format="Q{{urn:f}}text"><r>a<x>b</x></r></xsl:result-document></xsl:template>
<xsl:output name="Q{urn:f}text" method="text"/>
</xsl:stylesheet>
