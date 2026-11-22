<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:local="urn:local" exclude-result-prefixes="xs local">
<!-- xsl:iterate: parameters, xsl:next-iteration, xsl:break, xsl:on-completion -->
<xsl:template match="/">
<r>
  <a><xsl:iterate select="//item">
    <xsl:param name="total" as="xs:decimal" select="0"/>
    <xsl:param name="names" select="''"/>
    <xsl:on-completion><done total="{$total}" names="{$names}"/></xsl:on-completion>
    <xsl:variable name="t" select="$total + xs:decimal(@price)"/>
    <i pos="{position()}" last="{last()}" total="{$t}" cur="{current()/@n}"/>
    <xsl:next-iteration>
      <xsl:with-param name="total" select="$t"/>
      <xsl:with-param name="names" select="concat($names, @n)"/>
    </xsl:next-iteration>
  </xsl:iterate></a>
  <b><xsl:iterate select="//item">
    <xsl:param name="total" as="xs:decimal" select="0"/>
    <xsl:on-completion select="'never'"/>
    <xsl:choose>
      <xsl:when test="$total + xs:decimal(@price) gt 7">
        <xsl:break><stop at="{@n}" total="{$total}"/></xsl:break>
      </xsl:when>
      <xsl:otherwise>
        <xsl:value-of select="@n"/>
        <xsl:next-iteration>
          <xsl:with-param name="total" select="$total + xs:decimal(@price)"/>
        </xsl:next-iteration>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:iterate></b>
  <c><xsl:iterate select="1 to 5">
    <xsl:param name="kept" select="'k'"/>
    <xsl:param name="p" as="xs:integer?"/>
    <xsl:value-of select="concat(., $kept, $p, ' ')"/>
    <xsl:choose>
      <xsl:when test=". = 2"><xsl:next-iteration><xsl:with-param name="p" select="."/></xsl:next-iteration></xsl:when>
      <xsl:when test=". = 4"><xsl:break select="'B'"/></xsl:when>
    </xsl:choose>
  </xsl:iterate></c>
  <d><xsl:iterate select="()">
    <xsl:param name="p" select="'empty'"/>
    <xsl:on-completion select="$p"/>
    <xsl:value-of select="."/>
  </xsl:iterate></d>
  <e><xsl:iterate select="1 to 3">
    <xsl:iterate select="('x', 'y', 'z')">
      <xsl:value-of select="."/>
      <xsl:if test=". = 'y'"><xsl:break/></xsl:if>
    </xsl:iterate>
    <xsl:value-of select="."/>
  </xsl:iterate></e>
  <g xml:space="preserve"><xsl:iterate select="1 to 2"> <xsl:param name="p" select="'p'"/> <xsl:on-completion>|</xsl:on-completion>  <!--c-->ok<xsl:value-of select="$p"/></xsl:iterate></g>
  <f><xsl:sequence select="count(local:f())"/>|<xsl:value-of select="local:f()" separator=","/></f>
</r>
</xsl:template>
<xsl:function name="local:f">
  <xsl:iterate select="10 to 12">
    <xsl:param name="acc" as="xs:integer*" select="()"/>
    <xsl:on-completion select="$acc, 0"/>
    <xsl:next-iteration><xsl:with-param name="acc" select="$acc, . * 2"/></xsl:next-iteration>
  </xsl:iterate>
</xsl:function>
</xsl:stylesheet>
