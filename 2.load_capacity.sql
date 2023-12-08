
CREATE TABLE ftBathCapacity (
	[UID] [int] IDENTITY(1,1) NOT NULL,
	ProductSize INT NULL,
	WOFixture INT NULL,
	BathCapacity BIGINT NULL
	)

INSERT INTO ftBathCapacity (ProductSize,WOFixture,BathCapacity)
VALUES 
	(3,2,960),
	(3,1,440),
	(2,2,960),
	(2,1,696),
	(1,2,960),
	(1,2,720)

