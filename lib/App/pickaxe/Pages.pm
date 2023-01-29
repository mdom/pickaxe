package App::pickaxe::Pages;
use Mojo::Base -signatures, -base;

has array  => sub { [] };
has pos    => 0;
has oldpos => 0;

sub select ( $self, $offset ) {
    return if $self->empty;
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
    $self->select( $self->pos );
}

sub replace ($self, $pages) {
    $self->array( $pages );
    $self->pos(0);
    $self->oldpos(0);
}

sub next ($self) {
    $self->select( $self->pos + 1 );
}

sub each ($self) {
    @{ $self->array };
}

sub prev ($self) {
    $self->select( $self->pos - 1 );
}

sub current ($self) {
    $self->array->[ $self->pos ];
}

sub set ( $self, $elt ) {
    $self->array->[ $self->pos ] = $elt;
}

sub rewind ($self) {
    $self->select(0);
}

sub count ($self) {
    @{ $self->array } + 0;
}

sub empty ($self) {
    !@{ $self->array }
}

1;
