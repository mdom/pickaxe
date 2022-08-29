package App::pickaxe::Pages;
use Mojo::Base -signatures, -base;

has array  => sub { [] };
has pos    => 0;
has oldpos => 0;

sub seek ( $self, $offset ) {
    $self->oldpos( $self->pos );
    $self->pos($offset);
    if ( $self->pos < 0 ) {
        $self->pos(0);
    }
    elsif ( $self->pos > @{ $self->array } - 1 ) {
        $self->pos( @{ $self->array } - 1 );
    }
    return;
}

sub delete ( $self ) {
    splice(@{$self->array}, $self->pos, 1 );
    $self->seek( $self->pos );
}

sub replace ($self, $pages) {
    $self->array( $pages );
    $self->pos(0);
    $self->oldpos(0);
}

sub next ($self) {
    $self->seek( $self->pos + 1 );
}

sub each ($self) {
    @{ $self->array };
}

sub prev ($self) {
    $self->seek( $self->pos - 1 );
}

sub current ($self) {
    $self->array->[ $self->pos ];
}

sub set ( $self, $elt ) {
    $self->array->[ $self->pos ] = $elt;
}

sub rewind ($self) {
    $self->seek(0);
}

sub count ($self) {
    @{ $self->array } + 0;
}

sub empty ($self) {
    !@{ $self->array }
}

1;
