{ writeShellApplication, website, webfs, agate, http-port ? 4000, gmi-port ? 1965 }: writeShellApplication {
  name = "serve";
  runtimeInputs = [ webfs agate ];
  text = ''
    echo "Serving on: http://localhost:${toString http-port} and gemini://localhost:${toString gmi-port}"
    webfsd -f index.html -d -F -p ${toString http-port} -r ${website}/public & \
    agate --content ${website}/public --hostname localhost --certs /tmp/agate-certs --addr "0.0.0.0:${toString gmi-port}" & \

    jobs=$(jobs -p)
    trap 'kill $jobs' EXIT
    wait
  '';
}
