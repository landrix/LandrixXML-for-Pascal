<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- generate-id() as Saxon writes it (the ids of attributes differ: not
     shown); equal for the same node, different for others -->
<xsl:template match="/">
  <xsl:variable name="t"><x><y/></x></xsl:variable>
  <o ids="{for $n in //node() return generate-id($n)}" doc="{generate-id()}" tmp="{generate-id($t), generate-id($t/x/y)}"
    same="{generate-id(/r/a) = generate-id((//a)[1])}" attr="{generate-id(/r/a/@x) != generate-id(/r/a)}"
    empty="[{generate-id(())}]"/>
</xsl:template>
</xsl:stylesheet>
