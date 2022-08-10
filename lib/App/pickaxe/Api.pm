package App::pickaxe::Api;
use Mojo::Base -signatures, -base;
use Mojo::UserAgent;

has ua => sub { Mojo::UserAgent->new };

sub get ($self, $url) {
    $self->ua->get( $url => { 'Content-Type' => 'application/json' } )->result;
}

sub put ($self, $url, $text ) {
    $self->ua->put( $url => json => { wiki_page => { text => $text } } );
}

1;
