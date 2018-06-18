mkdir -p /data/apps

# import into the environment
. /data/Wing/bin/dataapps.sh

cd perl-5.26.2
./Configure -Dprefix=/data/apps -des
make
make install
cd ..

cd beanstalkd-1.10
make
make install PREFIX=/data/apps
cd ..

cpan App::cpanminus

