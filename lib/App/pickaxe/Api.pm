package App::pickaxe::Api;
use Mojo::Base -signatures, -base;
use Mojo::UserAgent;

has ua => sub { Mojo::UserAgent->new };
has 'base_url';

sub get ($self, $path, %parameters) {
    my $url = $self->base_url->clone->path($path);
    if ( %parameters ) {
        $url->query->merge( %parameters );
    }
    $self->ua->get( $url => { 'Content-Type' => 'application/json' } )->result;
}

sub put ($self, $path, $text ) {
    my $url = $self->base_url->clone->path($path);
    $self->ua->put( $url => json => { wiki_page => { text => $text } } );
}

1;
