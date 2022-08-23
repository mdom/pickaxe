package App::pickaxe::Api;
use Mojo::Base -signatures, -base;
use Mojo::UserAgent;

has ua => sub { Mojo::UserAgent->new };
has 'base_url';

sub get ( $self, $path, %parameters ) {
    my $url = $self->base_url->clone->path($path);
    if (%parameters) {
        $url->query->merge(%parameters);
    }
    my $res = eval {
        $self->ua->get( $url => { 'Content-Type' => 'application/json' } )
          ->result;
    };
    if ($@) {
        $@ =~ s/ at .*//;
        $@ =~ s/\s*$//;
        die("$@\n");
    }

    if ( !$res->is_success ) {
        die( $res->message . "\n" );
    }
    return $res;
}

sub url_for ( $self, $title ) {
    my $url = $self->base_url->clone->path("wiki/$title");
    $url->query( key => undef );
    return $url->to_string;
}

sub text_for ( $self, $title ) {
    $self->get("wiki/$title.json")->json->{wiki_page}->{text};
}

sub put ( $self, $path, $text ) {
    my $url = $self->base_url->clone->path($path);
    my $res =
      $self->ua->put( $url => json => { wiki_page => { text => $text } } )
      ->result;
    if ( !$res->is_success ) {
        die $res->message . "\n";
    }
    return $res;
}

sub delete ( $self, $title ) {
    my $url = $self->base_url->clone->path("wiki/$title.json");
    my $res = $self->ua->delete( $url )->result;
    if ( !$res->is_success ) {
        die $res->message . "\n";
    }
    return $res;
}

sub pages ($self) {
    $self->get("wiki/index.json")->json->{wiki_pages};
}

sub save ( $self, $title, $text ) {
    $self->put( "wiki/$title.json", $text );
}

sub page ( $self, $title ) {
    $self->get("wiki/$title.json");
}

sub search ( $self, $query ) {
    my $res = $self->get(
        "search.json",
        q          => $query,
        wiki_pages => 1,
        limit      => 100,
        offset     => 0
    );
    return if !$res->is_success;
    my $data           = $res->json;
    my @matching_pages = @{ $data->{results} };

    return if !@matching_pages;

    my $total_count = $data->{total_count};
    my $offset      = $data->{offset};
    while ( $total_count != @matching_pages ) {
        my $res = $self->get(
            "search.json",
            q          => $query,
            wiki_pages => 1,
            limit      => 100,
            offset     => $offset + 100,
        );
        return if !$res->is_success;
        my $data = $res->json;
        $offset = $data->{offset};
        push @matching_pages, @{ $data->{results} };
    }

    my %pages = map { $_->{title} => $_ } @{ $self->pages };
    @matching_pages =
      map { $pages{ $_->{title} =~ s/^Wiki: //r } } @matching_pages;
    return \@matching_pages;
}

1;
