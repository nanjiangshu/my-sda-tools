if [ -f ~/Downloads/s3cmd-inbox.conf ]; then
    mv -f ~/Downloads/s3cmd-inbox.conf .
fi

if [ -f ~/Downloads/s3cmd-download.conf ]; then
    mv -f ~/Downloads/s3cmd-download.conf .
fi

rm -f test_dir1/*.c4gh

sed -i  '/host_/s/inbox:8000/localhost:18000/g' s3cmd-inbox.conf # on Mac
sed -i  '/host_/s/inbox:8000/localhost:18000/g' s3cmd-download.conf # on Mac
sed -i  's/use_https = True/use_https = False/g' s3cmd-inbox.conf # on Mac
sed -i  's/use_https = True/use_https = False/g' s3cmd-download.conf # on Mac  

export ACCESS_TOKEN=$(grep token s3cmd-inbox.conf | awk '{print $3}')
