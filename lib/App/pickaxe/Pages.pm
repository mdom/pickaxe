package App::pickaxe::Pages;
use Mojo::Base -signatures, -base;

has index => 0;
has array => sub { [] };

sub new ($class, $array = []) {
    bless { array => $array }, $class;
}

sub current ($self, $page = undef) {
    $self->pages->array->[ $self->index ] = $page if $page;
    return $self->array->[ $self->index ];
}

sub delete_current ( $self ) {
    delete $self->array->[ $self->index ];
}

sub set ( $self, $pages ) {
    $self->array($pages);
    if ( $self->index >= $self->count ) {
        $self->index( $self->count - 1 );
    }
    return $self;
}

sub next ( $self ) {
    $self->set_index( $self->index + 1 );
}

sub prev ( $self ) {
    $self->set_index( $self->index + -1 );
}

sub set_index ( $self, $index ) {
    $self->index( $index );
    if ( $index < 0 ) {
        $self->index(0);
    }
    elsif ( $self->index >= $self->count ) {
        $self->index( $self->count - 1 );
    }
}

sub count ( $self ) {
    scalar $self->array->@*;
}

sub each ( $self ) {
    $self->array->@*;
}

sub empty ( $self ) {
    $self->count == 0;
}

1;
