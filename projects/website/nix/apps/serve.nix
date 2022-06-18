{ writeShellApplication, misterio-me, webfs, agate }: writeShellApplication {
  name = "serve";
  runtimeInputs = [ webfs agate ];
  text = ''
    echo "Serving on: http://localhost:8080 and gemini://localhost:1965"
    webfsd -f index.html -d -F -p 4000 -r ${misterio-me}/public & \
    agate --content ${misterio-me}/public --hostname localhost --certs /tmp/agate-certs & \

    jobs=$(jobs -p)
    trap 'kill $jobs' EXIT
    wait
  '';
}
