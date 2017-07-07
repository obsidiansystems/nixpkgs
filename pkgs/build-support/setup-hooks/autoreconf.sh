preConfigurePhases+=" autoreconfPhase"

for i in @autoconf@ @automake@ @libtool@ @gettext@; do
    findInputs $i -1
done

autoreconfPhase() {
    runHook preAutoreconf
    autoreconf ${autoreconfFlags:---install --force --verbose}
    runHook postAutoreconf
}
