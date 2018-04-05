FROM osrm/osrm-backend:v5.16.4

ARG PBF_DATA=http://download.geofabrik.de/russia-latest.osm.pbf
RUN mkdir /data
WORKDIR /data
RUN curl -L -f $PBF_DATA --create-dirs -o /data/data.osm.pbf && \
    osrm-extract -p /opt/car.lua /data/data.osm.pbf
    rm -f /data/data.osm.pbf && \
    osrm-partition /data/data.osrm && \
    osrm-customize /data/data.osrm

EXPOSE 5000

CMD ["osrm-routed", "--algorithm mld", "/data/data.osrm"]
