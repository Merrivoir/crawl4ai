FROM caddy:2.11.3
COPY dist/ /srv/
CMD ["caddy", "file-server", "--root", "/srv", "--listen", ":8080"]
