pip=$(which pip)
if [ ! $pip ];then
  curl https://bootstrap.pypa.io/2.6/get-pip.py -o get-pip.py
  python get-pip.py
  rm get-pip.py
fi
pip install prometheus-client
sed -i -e 's/{}.{}{}/{0}.{1}{2}/g' -e 's/{}e+0{}/{0}e+0{1}/g' /usr/lib/python2.6/site-packages/prometheus_client/utils.py
