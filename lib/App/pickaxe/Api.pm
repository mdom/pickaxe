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

sub pages ($self) {
    $self->get("wiki/index.json")->json->{wiki_pages};
}

sub search ( $self, $query ) {
    my $res = $self->get(
        "search.json",
        q          => $query,
        wiki_pages => 1,
        limit      => 100,
        offset     => 0
    );
    my $result  = $res->json;
    my @results = @{ $res->json->{results} };

    return if !@results;

    my %pages = map { $_->{title} => $_ } @{ $self->pages };

    my @found;
    for my $result (@results) {
        $result->{title} =~ s/^Wiki: //;
        push @found, $pages{ $result->{title} };
    }
    return \@found;
}

1;
