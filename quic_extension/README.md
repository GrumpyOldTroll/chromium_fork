
After `git clone https://github.com/GrumpyOldTroll/chromium_fork` and `cd chromium_fork/quic_extension`, we basically follow the directions for [building chromium on Linux](https://chromium.googlesource.com/chromium/src/+/main/docs/linux/build_instructions.md), but pull in the multicast source from a fork and change the build command to build quic_server and quic_client instead.

If you're feeling brave, pasting this **should** theoretically work, but I recommend going thru it a small piece at a time to make sure each piece works for you.  Note that the `fetch chromium` step will probably take something like 3-5 hours.

~~~
#sudo apt install -y python-is-python3
sudo apt-get install -y python3-venv
mkdir -p ~/venv
python3 -m venv ~/venv/quicmc
source ~/venv/quicmc/bin/activate

if ! which fetch; then
  mkdir -p ${HOME}/local_install
  pushd ${HOME}/local_install
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
  export PATH=${PATH}:${HOME}/local_install/depot_tools
  popd
else
  pushd $(dirname $(which fetch))
  git checkout main
  git pull origin main
  popd
fi

#VERSION=$(curl https://omahaproxy.appspot.com/all.json | jq -r '.[].versions[] | select(.os=="linux") | select(.channel=="dev") | .version' | head -1)
#VERSION=$(cat QUIC_VERSION_BASE.txt)

mkdir -p work
cd work
fetch chromium --no-history
cd src/

mkdir -p out/Default
cat > out/Default/args.gn <<EOF
is_debug=true
is_component_build=false
blink_symbol_level=1
symbol_level=1
enable_nacl=false
enable_linux_installer=true
ffmpeg_branding="Chrome"
proprietary_codecs=true
EOF

git remote add multicast git@github.com:GrumpyOldTroll/chromium.git
# or https://github.com/GrumpyOldTroll/chromium.git
git fetch multicast
git checkout quic-multicast-dev
git checkout -b my-working-chromium-branch

pushd net/third_party/quiche/src
git remote add multicast git@github.com:GrumpyOldTroll/quiche.git
git fetch multicast
git checkout quic-multicast-dev
git checkout -b my-working-quiche-branch
popd

./build/install-build-deps.sh --no-prompt
gclient sync
gn gen out/Default

ninja -C out/Default epoll_quic_server epoll_quic_client

pushd net/tools/quic/certs
./generate-certs.sh
popd
mkdir -p /tmp/quic-data
pushd /tmp/quic-data
wget -p --save-headers https://www.example.org

# manually edit index.html
# (as in https://www.chromium.org/quic/playing-with-quic/):
#   Remove (if it exists):
#     "Transfer-Encoding: chunked"
#     "Alternate-Protocol: ..."
#   Add:
#     X-Original-Url: https://www.example.org/
# note: it's very touchy about the url in X-Original-Url

popd

./out/Default/epoll_quic_server --quic_ietf_draft \
  --quic_response_cache_dir=/tmp/quic-data/www.example.org \
  --certificate_file=net/tools/quic/certs/out/leaf_cert.pem \
  --key_file=net/tools/quic/certs/out/leaf_cert.pkcs8


./out/Default/epoll_quic_client --host=127.0.0.1 --port=6121 \
  --disable_certificate_verification https://www.example.org/
~~~

If you want to run chromium vs. the quic_server, I recommend using a new profile and also you'll need to pass your local generated key's fingerprint, as well as telling chromium to use your quic server instead of dns:

~~~
openssl x509 -pubkey < "net/tools/quic/certs/out/leaf_cert.pem" | \
  openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | \
  base64 > "/tmp/fingerprints.txt"

mkdir -p /tmp/chrome-tmp-profile/Default
touch "/tmp/chrome-tmp-profile/First Run"
echo '{ "browser": { "has_seen_welcome_page": true }}' > /tmp/chrome-tmp-profile/Default/Preferences


# for more limited logging, a tab with chrome://net-export instead.
# https://www.chromium.org/for-testers/providing-network-details

google-chrome --user-data-dir=/tmp/chrome-tmp-profile --no-proxy-server \
  --enable-quic --origin-to-force-quic-on=www.example.org:443 \
  --host-resolver-rules='MAP www.example.org:443 127.0.0.1:6121' \
  --ignore-certificate-errors-spki-list=$(cat /tmp/fingerprints.txt) \
  --log-net-log=/tmp/chrome-net-log.json https://www.example.org/
~~~

---

Notes:

Originally (and according to the "playing with quic" instructions) this used quic_server and quic_client instead of epoll_quic_server and epoll_quic_client.

These appear to have similar behavior (and both specifically disclaim any performant operation), but e.g. epoll_quic_server has entry points at net/third_party/quiche/src/quic/tools/quic_server.cc instead of net/tools/quic/quic_simple_server.cc, and at net/third_party/quiche/src/quic/tools/quic_server_bin.cc instead of net/tools/quic/quic_simple_server_bin.cc.  (Notably, both of these use net/third_party/quiche/src/quic/tools/quic_toy_server.cc.)

I propose to do our initial work on the epoll implementation in net/third_party/quiche/src/quic instead of the "simple" implementation in net/tools/quic, where we have any divergence.  (And we will need to have some early divergence, specifically in the pipe handling at the root's pusher.)

I'll rate it a nice-to-have to include a non-epoll version as well (and probably necessary before a one-day upstream PR) but I'll assign it a low priority while we're doing an initial pass.

